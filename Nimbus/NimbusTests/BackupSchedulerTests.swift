import AppKit
import Foundation
import Testing
@testable import Nimbus

/// A clock the test moves by hand. Sleepers resume only inside `advance`,
/// so nothing depends on wall time.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var cancelledIDs: Set<Int> = []
    private var nextID = 0
    private var sleepCalls = 0
    /// Each waiter's condition is checked under the lock after every change.
    private var waiters: [(isReady: () -> Bool, continuation: CheckedContinuation<Void, Never>)] = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// Seconds the clock has moved since it was created.
    var elapsed: TimeInterval {
        let parts = now.offset.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    /// Sleepers still waiting.
    var pendingSleepers: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = registerSleepCall()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if cancelledIDs.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                } else {
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    let ready = takeReadyWaiters()
                    lock.unlock()
                    ready.forEach { $0.resume() }
                }
            }
        } onCancel: {
            lock.lock()
            if let index = sleepers.firstIndex(where: { $0.id == id }) {
                let sleeper = sleepers.remove(at: index)
                let ready = takeReadyWaiters()
                lock.unlock()
                sleeper.continuation.resume(throwing: CancellationError())
                ready.forEach { $0.resume() }
            } else {
                cancelledIDs.insert(id)
                lock.unlock()
            }
        }
    }

    func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        let ready = takeReadyWaiters()
        lock.unlock()
        for sleeper in due { sleeper.continuation.resume() }
        ready.forEach { $0.resume() }
    }

    /// Returns once `sleep` has been called at least `count` times in total.
    func waitForSleepCalls(_ count: Int) async {
        await waitUntil { self.sleepCalls >= count }
    }

    /// Returns once exactly `count` sleepers are waiting.
    func waitForPendingSleepers(_ count: Int) async {
        await waitUntil { self.sleepers.count == count }
    }

    /// `isReady` runs under the lock.
    private func waitUntil(_ isReady: @escaping () -> Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isReady() {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((isReady, continuation))
                lock.unlock()
            }
        }
    }

    private func registerSleepCall() -> Int {
        lock.lock()
        nextID += 1
        sleepCalls += 1
        let id = nextID
        let ready = takeReadyWaiters()
        lock.unlock()
        ready.forEach { $0.resume() }
        return id
    }

    /// Call with the lock held; resume the result after unlocking.
    private func takeReadyWaiters() -> [CheckedContinuation<Void, Never>] {
        let ready = waiters.filter { $0.isReady() }
        waiters.removeAll { $0.isReady() }
        return ready.map(\.continuation)
    }
}

/// Records what the scheduler asks to run. Like the real runner, it treats a
/// started job as busy and records its run (which re-plans via the store).
/// Like the runner's `startSync`, it notices if its task is cancelled.
@MainActor
final class RecordingLauncher: BackupLaunching {
    private(set) var calls: [(jobID: UUID, trigger: BackupRunSummary.Trigger)] = []
    /// Enqueues that ran on a cancelled task (a real start request would fail).
    private(set) var cancelledEnqueues = 0
    /// Jobs whose enqueue hasn't returned yet: the scheduler's `busy` set.
    private(set) var inFlight: Set<UUID> = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private let store: BackupStore
    private let now: () -> Date

    init(store: BackupStore, now: @escaping () -> Date) {
        self.store = store
        self.now = now
    }

    func enqueue(_ jobID: UUID, trigger: BackupRunSummary.Trigger) async {
        calls.append((jobID, trigger))
        inFlight.insert(jobID)
        defer { inFlight.remove(jobID) }
        var wasCancelled = Task.isCancelled
        let started = now()
        await store.recordRun(id: jobID, summary: BackupRunSummary(
            startedAt: started, finishedAt: started, trigger: trigger, outcome: .completed,
            copied: 0, replaced: 0, removed: 0, errors: 0, bytes: 0
        ))
        wasCancelled = wasCancelled || Task.isCancelled
        if wasCancelled { cancelledEnqueues += 1 }
        // Waiters resume once the call (and its re-plan) is done.
        let ready = waiters.filter { $0.count <= calls.count }
        waiters.removeAll { $0.count <= calls.count }
        for waiter in ready { waiter.continuation.resume() }
    }

    func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

@Suite("BackupScheduler", .serialized, .timeLimit(.minutes(1)))
@MainActor
final class BackupSchedulerTests {
    static let start = BackupJobTests.date("2026-11-10T09:00:00-05:00")

    let clock = ManualClock()
    let workspaceCenter = NotificationCenter()
    let systemCenter = NotificationCenter()
    /// Wall time that passes without the clock moving (the Mac asleep).
    var asleepFor: TimeInterval = 0
    var store: BackupStore!
    var launcher: RecordingLauncher!
    var scheduler: BackupScheduler!

    var now: Date { Self.start.addingTimeInterval(clock.elapsed + asleepFor) }

    private func setUp(_ jobs: [BackupJob]) async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupSchedulerTests-\(UUID().uuidString)", isDirectory: true)
        let store = BackupStore(file: BackupsFile(url: dir.appendingPathComponent("backups-v1.json")))
        await store.load()
        for job in jobs { await store.upsert(job) }
        let launcher = RecordingLauncher(store: store, now: { [unowned self] in now })
        let scheduler = BackupScheduler(
            store: store, launcher: launcher, planner: BackupSchedulePlanner(calendar: BackupJobTests.newYork),
            clock: clock, now: { [unowned self] in now }, settleDelay: .seconds(60),
            busy: { [unowned launcher] in launcher.inFlight },
            workspaceCenter: workspaceCenter, systemCenter: systemCenter
        )
        store.onJobsChanged = { [weak scheduler] in scheduler?.replan() }
        self.store = store
        self.launcher = launcher
        self.scheduler = scheduler
    }

    private func advance(to date: Date) {
        clock.advance(by: .seconds(date.timeIntervalSince(now)))
    }

    private static func job(lastRunStart: String, hour: Int = 2) -> BackupJob {
        BackupSchedulePlannerTests.job(
            schedule: .daily(hour: hour, minute: 0),
            lastRunStart: BackupJobTests.date(lastRunStart)
        )
    }

    @Test func startEnqueuesDueJobsAfterSettle() async throws {
        let job = Self.job(lastRunStart: "2026-11-07T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)

        clock.advance(by: .seconds(59))
        #expect(clock.pendingSleepers == 1) // the deadline has not been reached
        #expect(launcher.calls.isEmpty)

        clock.advance(by: .seconds(1))
        await launcher.waitForCalls(1)
        // The recorded run moves the job to tomorrow; the re-plan sleeps until then.
        await clock.waitForSleepCalls(2)
        #expect(launcher.calls.count == 1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .catchUp)
        scheduler.stop()
    }

    @Test func timerFiresAtNextWake() async throws {
        let job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2)
        #expect(launcher.calls.isEmpty)

        advance(to: BackupJobTests.date("2026-11-11T01:59:59-05:00"))
        #expect(clock.pendingSleepers == 1)
        #expect(launcher.calls.isEmpty)

        advance(to: BackupJobTests.date("2026-11-11T02:00:00-05:00"))
        await launcher.waitForCalls(1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .scheduled)
        scheduler.stop()
    }

    @Test func replanAfterEditMovesTimer() async throws {
        var job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2) // asleep until tomorrow 02:00

        job.schedule = .daily(hour: 10, minute: 0)
        await store.upsert(job)
        // No settle delay for an edit: the timer re-arms straight away.
        await clock.waitForSleepCalls(3)
        #expect(clock.pendingSleepers == 1)

        advance(to: BackupJobTests.date("2026-11-10T10:00:00-05:00"))
        await launcher.waitForCalls(1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .scheduled)
        scheduler.stop()
    }

    @Test func wakeTriggersCatchUp() async throws {
        let job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2)

        // The Mac sleeps through tomorrow's 02:00 slot.
        asleepFor = 2 * 24 * 3600
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await clock.waitForSleepCalls(3)
        #expect(launcher.calls.isEmpty)

        clock.advance(by: .seconds(59))
        #expect(clock.pendingSleepers == 1) // the deadline has not been reached
        #expect(launcher.calls.isEmpty)
        clock.advance(by: .seconds(1))
        await launcher.waitForCalls(1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .catchUp)
        scheduler.stop()
    }

    @Test(arguments: [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange])
    func clockChangeCatchesUpAfterSettle(_ name: Notification.Name) async throws {
        let job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2) // asleep until tomorrow 02:00

        // The wall clock jumps past tomorrow's slot; the timer's clock doesn't.
        asleepFor = 2 * 24 * 3600
        systemCenter.post(name: name, object: nil)
        await clock.waitForSleepCalls(3)
        #expect(clock.pendingSleepers == 1)
        #expect(launcher.calls.isEmpty)

        clock.advance(by: .seconds(59))
        #expect(clock.pendingSleepers == 1) // the deadline has not been reached
        #expect(launcher.calls.isEmpty)
        clock.advance(by: .seconds(1))
        await launcher.waitForCalls(1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .catchUp)
        scheduler.stop()
    }

    @Test func lateTimerWaitsForSettle() async throws {
        let job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2) // asleep until tomorrow 02:00

        // The timer fires six minutes after its slot.
        advance(to: BackupJobTests.date("2026-11-11T02:06:00-05:00"))
        await clock.waitForSleepCalls(3) // re-armed for the settle delay
        #expect(launcher.calls.isEmpty)

        clock.advance(by: .seconds(59))
        #expect(clock.pendingSleepers == 1) // the deadline has not been reached
        #expect(launcher.calls.isEmpty)
        clock.advance(by: .seconds(1))
        await launcher.waitForCalls(1)
        await clock.waitForSleepCalls(4) // the recorded run re-plans for the next day
        #expect(launcher.calls.count == 1)
        let call = try #require(launcher.calls.first)
        #expect(call.jobID == job.id)
        #expect(call.trigger == .catchUp)
        scheduler.stop()
    }

    @Test func timerWithinThresholdRunsAtOnce() async throws {
        let job = Self.job(lastRunStart: "2026-11-10T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        clock.advance(by: .seconds(60))
        await clock.waitForSleepCalls(2)

        advance(to: BackupJobTests.date("2026-11-11T02:04:00-05:00"))
        await launcher.waitForCalls(1)
        #expect(launcher.calls.first?.trigger == .scheduled)
        scheduler.stop()
    }

    @Test func replanDuringPassDoesNotCancelStarts() async throws {
        let first = Self.job(lastRunStart: "2026-11-07T02:00:00-05:00")
        let second = Self.job(lastRunStart: "2026-11-07T02:00:00-05:00")
        await setUp([first, second])
        scheduler.start()
        await clock.waitForSleepCalls(1)

        // Each recorded run re-plans mid-pass; the starts must not see that.
        clock.advance(by: .seconds(60))
        await launcher.waitForCalls(2)
        #expect(Set(launcher.calls.map(\.jobID)) == [first.id, second.id])
        #expect(launcher.cancelledEnqueues == 0)

        // Once the pass ends, one timer is armed for tomorrow's slot.
        await clock.waitForPendingSleepers(1)
        advance(to: BackupJobTests.date("2026-11-11T02:00:00-05:00"))
        await launcher.waitForCalls(4)
        #expect(launcher.calls.suffix(2).allSatisfy { $0.trigger == .scheduled })
        #expect(launcher.cancelledEnqueues == 0)
        scheduler.stop()
    }

    @Test func stopCancelsTimer() async {
        let job = Self.job(lastRunStart: "2026-11-07T02:00:00-05:00")
        await setUp([job])
        scheduler.start()
        await clock.waitForSleepCalls(1)
        scheduler.stop()
        #expect(clock.pendingSleepers == 0)
        clock.advance(by: .seconds(3600))
        // Neither a replan nor a wake restarts a stopped scheduler.
        scheduler.replan()
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(clock.pendingSleepers == 0)
        #expect(launcher.calls.isEmpty)
    }
}
