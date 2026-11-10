import Foundation
import Testing
import RcloneKit
@testable import Nimbus

@Suite("BackupRunner", .serialized)
@MainActor
struct BackupRunnerTests {
    let now = Date(timeIntervalSince1970: 1_794_085_200) // 2026-11-08 16:00:00 EST

    struct Harness {
        let runner: BackupRunner
        let store: BackupStore
        let transfers: TransferStore
        let client: MockBackupClient
        let activity: ActivityRecorder
    }

    /// Stands in for `ProcessInfo` begin/endActivity.
    @MainActor
    final class ActivityRecorder {
        private(set) var reasons: [String] = []
        private(set) var ended = 0
        var isHeld: Bool { reasons.count > ended }

        func begin(_ reason: String) -> any NSObjectProtocol {
            reasons.append(reason)
            return NSObject()
        }

        func end(_ token: any NSObjectProtocol) { ended += 1 }
    }

    private func harness(connected: Bool = true) async -> Harness {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupRunnerTests-\(UUID().uuidString)", isDirectory: true)
        let store = BackupStore(file: BackupsFile(url: dir.appendingPathComponent("backups-v1.json")))
        await store.load()
        let transfers = TransferStore(history: InMemoryTransferHistory())
        let client = MockBackupClient()
        let activity = ActivityRecorder()
        let runner = BackupRunner(store: store, transfers: transfers, client: client,
                                  isDaemonConnected: { connected }, now: { self.now },
                                  timeZone: { TimeZone(identifier: "America/New_York")! },
                                  beginActivity: activity.begin, endActivity: activity.end)
        return Harness(runner: runner, store: store, transfers: transfers, client: client, activity: activity)
    }

    private func addJob(_ h: Harness, name: String = "Docs", approved: Bool = true,
                        _ mutate: (inout BackupJob) -> Void = { _ in }) async -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/\(name)"),
                                destination: .cloud(remote: "b2", path: name), now: now)
        job.name = name
        mutate(&job)
        await h.store.upsert(job)
        if approved { await h.store.approve(id: job.id, fingerprint: job.fingerprint, now: now) }
        return h.store.job(id: job.id)!
    }

    private func finish(_ h: Harness, rcloneJob: Int, success: Bool = true, error: String = "") async {
        await h.transfers.handleFinished(
            jobID: rcloneJob,
            job: BackupFixtures.job(id: rcloneJob, finished: true, success: success, error: error),
            stats: BackupFixtures.stats(transfers: 3, deletes: 1, renames: 2),
            now: now.addingTimeInterval(60)
        )
    }

    @Test func unapprovedJobIsRefused() async {
        let h = await harness()
        let job = await addJob(h, approved: false)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .notApproved)
        #expect(h.runner.queue.isEmpty)
    }

    @Test func daemonDownIsRefused() async {
        let h = await harness(connected: false)
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .daemonNotConnected)
    }

    @Test func approvedJobStartsWithRealRequest() async throws {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        let request = try #require(h.client.requests.first)
        #expect(request.dryRun == false)
        #expect(request.reports.isEmpty)
        let stamp = BackupRequest.stamp(for: now)
        #expect(request.backupDir == "b2:Docs/.nimbus-versions/\(stamp)")
        #expect(h.runner.runningJobID == job.id)
        let transfer = try #require(h.transfers.activeTransfers.first)
        #expect(transfer.origin == .backup)
        #expect(transfer.backup?.title == "Docs")
        #expect(transfer.backup?.hadRemovalLimit == true)
        #expect(transfer.backup?.isMirrorWithVersions == true)
        #expect(transfer.jobID == 100)
    }

    @Test func secondEnqueueOfSameJobIsRefused() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.lastRefusal == .alreadyQueuedOrRunning)
    }

    @Test func jobsRunOneAtATime() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .scheduled)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.queue == [second.id])

        await finish(h, rcloneJob: 100)
        #expect(h.client.requests.count == 2)
        #expect(h.client.requests.last?.srcFs == "/Users/j/B")
        #expect(h.runner.runningJobID == second.id)
        #expect(h.transfers.activeTransfers.first?.backup?.trigger == .scheduled)
    }

    @Test func finishRecordsLastRun() async throws {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100)
        let lastRun = try #require(h.store.job(id: job.id)?.lastRun)
        #expect(lastRun.outcome == .completed)
        #expect(lastRun.copied == 3)
        #expect(lastRun.removed == 1)
        #expect(lastRun.replaced == 1)
        #expect(lastRun.trigger == .manual)
        #expect(h.runner.runningJobID == nil)
        #expect(h.runner.isRunningAnything == false)
    }

    /// The scheduler re-plans when the run is recorded; by then the job must
    /// no longer look busy, or an overdue next slot is never caught up.
    @Test func finishedJobIsNotBusyWhenItsRunIsRecorded() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .scheduled)
        var runningAtRecord: [UUID?] = []
        h.store.onJobsChanged = { [runner = h.runner] in runningAtRecord.append(runner.runningJobID) }
        await finish(h, rcloneJob: 100)
        #expect(runningAtRecord == [nil])
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .completed)
    }

    @Test func missingSourceMessage() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100, success: false, error: "directory not found")
        #expect(h.store.job(id: job.id)?.lastRun?.outcome
            == .failed("The source folder isn't available. Is the drive connected?"))
    }

    @Test func failedRunKeepsRemovalLimitAndVersionsFlag() async throws {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100, success: false, error: "directory not found")
        let lastRun = try #require(h.store.job(id: job.id)?.lastRun)
        #expect(lastRun.removalLimit == job.removalLimit)
        #expect(lastRun.movesToVersions == (job.mode == .mirror && job.versions.enabled))
    }

    @Test func limitHitRecorded() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.transfers.handleFinished(
            jobID: 100,
            job: BackupFixtures.job(id: 100, finished: true, success: false, error: "failed to delete 4 files"),
            stats: BackupFixtures.stats(transfers: 0, deletes: 100, renames: 0, lastError: "--max-delete threshold reached"),
            now: now
        )
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .limitHit)
    }

    @Test func daemonRestartUnsticksQueue() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.transfers.abandonActiveTransfers()
        #expect(h.store.job(id: first.id)?.lastRun?.outcome == .failed(TransferStore.lostRunMessage))
        #expect(h.runner.runningJobID == second.id)
    }

    @Test func editedJobAfterApprovalIsRefused() async {
        let h = await harness()
        var job = await addJob(h)
        job.destination = .cloud(remote: "b2", path: "elsewhere")
        await h.store.upsert(job)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .notApproved)
    }

    @Test func startFailureRecordsFailedRunAndContinues() async {
        let h = await harness()
        let job = await addJob(h)
        h.client.failStarts(with: URLError(.cannotConnectToHost))
        await h.runner.enqueue(job.id, trigger: .manual)
        guard case .failed = h.store.job(id: job.id)?.lastRun?.outcome else {
            Issue.record("expected a failed lastRun")
            return
        }
        #expect(h.runner.runningJobID == nil)
    }

    @Test func stopCancelsAndStartsNext() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.runner.stop(first.id)
        #expect(h.client.stopped == [100])
        #expect(h.store.job(id: first.id)?.lastRun?.outcome == .cancelled)
        #expect(h.runner.runningJobID == second.id)
    }

    @Test func stopQueuedJobRemovesIt() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.runner.stop(second.id)
        #expect(h.runner.queue.isEmpty)
        #expect(h.client.stopped.isEmpty)
    }

    // MARK: Runs lost to a daemon restart

    static let planner = BackupSchedulePlanner(calendar: BackupJobTests.newYork)

    /// A daily 02:00 job that last ran two days ago, so it is due now.
    private func overdueJob(_ h: Harness) async -> BackupJob {
        let job = await addJob(h) { $0.schedule = .daily(hour: 2, minute: 0) }
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        await h.store.recordRun(id: job.id, summary: BackupRunSummary(
            startedAt: twoDaysAgo, finishedAt: twoDaysAgo.addingTimeInterval(60), trigger: .scheduled,
            outcome: .completed, copied: 0, replaced: 0, removed: 0, errors: 0, bytes: 0))
        return h.store.job(id: job.id)!
    }

    private func lostRunWasRecordedFailed(_ h: Harness, rcloneJob: Int) -> Bool {
        guard case .failed(let message)? = h.transfers.transfers.first(where: { $0.jobID == rcloneJob })?.status
        else { return false }
        return message == TransferStore.lostRunMessage
    }

    @Test func firstLossOfScheduledRunCountsAsMissed() async {
        let h = await harness()
        let job = await overdueJob(h)
        var lostCalls = 0
        h.runner.onRunLost = { lostCalls += 1 }
        await h.runner.enqueue(job.id, trigger: .catchUp)
        await h.transfers.abandonActiveTransfers(now: now)
        #expect(h.store.job(id: job.id)?.lastRun == job.lastRun)
        #expect(Self.planner.dueJobs(h.store.jobs, now: now, busy: h.runner.busyJobIDs) == [job.id])
        #expect(lostCalls == 1)
        // The Transfers list still shows what happened.
        #expect(lostRunWasRecordedFailed(h, rcloneJob: 100))
    }

    @Test func firstLossViaJobNotFoundCountsAsMissed() async {
        let h = await harness()
        let job = await overdueJob(h)
        await h.runner.enqueue(job.id, trigger: .scheduled)
        await h.transfers.handlePollFailure(
            jobID: 100, error: RcloneError.requestFailed(status: 500, message: "job not found"), now: now)
        #expect(h.store.job(id: job.id)?.lastRun == job.lastRun)
        #expect(h.runner.runningJobID == nil)
        #expect(lostRunWasRecordedFailed(h, rcloneJob: 100))
    }

    @Test func secondConsecutiveLossRecordsFailed() async {
        let h = await harness()
        let job = await overdueJob(h)
        await h.runner.enqueue(job.id, trigger: .catchUp)
        await h.transfers.abandonActiveTransfers(now: now)
        await h.runner.enqueue(job.id, trigger: .catchUp)
        await h.transfers.abandonActiveTransfers(now: now)
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .failed(TransferStore.lostRunMessage))
        #expect(Self.planner.dueJobs(h.store.jobs, now: now, busy: h.runner.busyJobIDs).isEmpty)
    }

    @Test func finishedRunResetsTheLossCount() async {
        let h = await harness()
        let job = await overdueJob(h)
        await h.runner.enqueue(job.id, trigger: .catchUp)
        await h.transfers.abandonActiveTransfers(now: now)
        await h.runner.enqueue(job.id, trigger: .catchUp)
        await finish(h, rcloneJob: 101)
        let completed = h.store.job(id: job.id)?.lastRun
        #expect(completed?.outcome == .completed)

        await h.runner.enqueue(job.id, trigger: .scheduled)
        await h.transfers.abandonActiveTransfers(now: now)
        #expect(h.store.job(id: job.id)?.lastRun == completed)
    }

    @Test func lostManualRunRecordsFailed() async {
        let h = await harness()
        let job = await overdueJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.transfers.abandonActiveTransfers(now: now)
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .failed(TransferStore.lostRunMessage))
    }

    // MARK: Pausing

    @Test func pausedJobsScheduledRunIsSkippedAtStart() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .catchUp)
        await h.store.setPaused(id: second.id, true)
        await finish(h, rcloneJob: 100)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.runningJobID == nil)
        #expect(h.store.job(id: second.id)?.lastRun == nil)
    }

    @Test func pausedJobsManualRunStillStarts() async {
        let h = await harness()
        h.store.onJobsChanged = { [runner = h.runner] in runner.jobsDidChange() }
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.store.setPaused(id: second.id, true)
        #expect(h.runner.queue == [second.id])
        await finish(h, rcloneJob: 100)
        #expect(h.runner.runningJobID == second.id)
    }

    @Test func pausingDropsQueuedScheduledRun() async {
        let h = await harness()
        h.store.onJobsChanged = { [runner = h.runner] in runner.jobsDidChange() }
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        let third = await addJob(h, name: "C")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .scheduled)
        await h.runner.enqueue(third.id, trigger: .scheduled)
        await h.store.setPaused(id: second.id, true)
        #expect(h.runner.queue == [third.id])
        #expect(!h.runner.isQueued(second.id))
    }

    // MARK: Starting

    @MainActor final class StartProbe {
        var refusal: BackupRunner.Refusal?
        var busy: Set<UUID> = []
        var isRunningAnything = false
    }

    @Test func enqueueWhileStartIsInFlightIsRefused() async {
        let h = await harness()
        let job = await addJob(h)
        let probe = StartProbe()
        h.client.onNextStart { [runner = h.runner] in
            await runner.enqueue(job.id, trigger: .scheduled)
            probe.refusal = runner.lastRefusal
            probe.busy = runner.busyJobIDs
            probe.isRunningAnything = runner.isRunningAnything
        }
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(probe.refusal == .alreadyQueuedOrRunning)
        #expect(probe.busy == [job.id])
        #expect(probe.isRunningAnything)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.queue.isEmpty)
        #expect(h.runner.runningJobID == job.id)
    }

    @Test func sleepIsHeldUntilQueueEmpties() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        #expect(!h.activity.isHeld)

        await h.runner.enqueue(first.id, trigger: .scheduled)
        await h.runner.enqueue(second.id, trigger: .scheduled)
        #expect(h.activity.reasons == ["Backing up A"])
        #expect(h.activity.isHeld)

        await finish(h, rcloneJob: 100)
        #expect(h.activity.isHeld)
        #expect(h.activity.reasons.count == 1)

        await finish(h, rcloneJob: 101)
        #expect(!h.activity.isHeld)
        #expect(h.activity.ended == 1)
    }

    @Test func failedStartDoesNotHoldSleep() async {
        let h = await harness()
        let job = await addJob(h)
        h.client.failStarts(with: URLError(.cannotConnectToHost))
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(!h.activity.isHeld)
    }

    // MARK: - Versions pruning

    /// Holds a call open until released.
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private func oldStamp() -> String {
        BackupRequest.stamp(for: now.addingTimeInterval(-40 * 86_400), timeZone: TimeZone(identifier: "America/New_York")!)
    }

    private func addPrunableJob(_ h: Harness, name: String = "Docs") async -> BackupJob {
        h.client.setListing(fs: "b2:", remote: "\(name)/.nimbus-versions", [BackupFixtures.listed(oldStamp())])
        return await addJob(h, name: name) { $0.versions.keep = .days30 }
    }

    @Test func completedRunPrunesOldVersions() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100)
        await h.runner.waitForPruning()
        #expect(h.client.purges == [.init(fs: "b2:", remote: "Docs/.nimbus-versions/\(oldStamp())")])
    }

    @Test func failedRunDoesNotPrune() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100, success: false, error: "boom")
        await h.runner.waitForPruning()
        #expect(h.client.listCalls.isEmpty)
        #expect(h.client.purges.isEmpty)
    }

    @Test func limitHitRunDoesNotPrune() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.transfers.handleFinished(
            jobID: 100,
            job: BackupFixtures.job(id: 100, finished: true, success: false, error: "failed to delete 4 files"),
            stats: BackupFixtures.stats(transfers: 0, deletes: 100, renames: 0, lastError: "--max-delete threshold reached"),
            now: now
        )
        await h.runner.waitForPruning()
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .limitHit)
        #expect(h.client.purges.isEmpty)
    }

    @Test func stoppedRunDoesNotPrune() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.runner.stop(job.id)
        await h.runner.waitForPruning()
        #expect(h.client.purges.isEmpty)
    }

    @Test func lostRunDoesNotPrune() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.transfers.abandonActiveTransfers(now: now)
        await h.runner.waitForPruning()
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .failed(TransferStore.lostRunMessage))
        #expect(h.client.purges.isEmpty)
    }

    @Test func slowPruneDoesNotDelayNextJob() async {
        let h = await harness()
        let first = await addPrunableJob(h, name: "A")
        let second = await addJob(h, name: "B")
        let gate = Gate()
        h.client.onList { await gate.wait() }
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await finish(h, rcloneJob: 100)
        #expect(h.client.requests.count == 2)
        #expect(h.runner.runningJobID == second.id)
        #expect(h.store.job(id: first.id)?.lastRun?.outcome == .completed)
        await gate.release()
        await h.runner.waitForPruning()
        #expect(h.client.purges.count == 1)
    }

    @Test func pruneFailureLeavesRunCompleted() async {
        let h = await harness()
        let job = await addPrunableJob(h)
        h.client.failLists(with: URLError(.timedOut))
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100)
        await h.runner.waitForPruning()
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .completed)
        #expect(h.client.purges.isEmpty)
        #expect(h.runner.isRunningAnything == false)
    }
}
