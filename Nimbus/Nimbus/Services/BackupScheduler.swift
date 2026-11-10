import AppKit
import Foundation

/// Decides which saved backups are due and when to wake next. Pure: the
/// caller supplies the clock and the set of jobs already queued or running.
///
/// A job's next run is the first slot after the start of its last attempt
/// (or after approval if it never ran). A failed run is not retried early,
/// and any number of missed slots yields a single run.
struct BackupSchedulePlanner {
    let calendar: Calendar

    /// Jobs whose next run is at or before `now`: scheduled, approved, not paused, not queued or running.
    func dueJobs(_ jobs: [BackupJob], now: Date, busy: Set<UUID>) -> [UUID] {
        jobs.compactMap { job in
            guard !busy.contains(job.id), let next = eligibleNextRun(for: job), next <= now else { return nil }
            return job.id
        }
    }

    /// The earliest future next run among eligible jobs, or nil.
    func nextWake(_ jobs: [BackupJob], now: Date) -> Date? {
        jobs.compactMap { eligibleNextRun(for: $0) }.filter { $0 > now }.min()
    }

    /// Anchor = lastRun?.startedAt ?? approvedAt ?? createdAt. Nil for manual jobs.
    func nextRun(for job: BackupJob) -> Date? {
        let anchor = job.lastRun?.startedAt ?? job.approvedAt ?? job.createdAt
        return job.schedule.nextRun(after: anchor, calendar: calendar)
    }

    private func eligibleNextRun(for job: BackupJob) -> Date? {
        guard job.isApproved, !job.isPaused else { return nil }
        return nextRun(for: job)
    }
}

/// Runs saved backups on their schedule while Nimbus is open. One task
/// sleeps until the earliest next run; it is re-created on every `replan`.
///
/// `start()` and catch-up re-plans (wake, daemon reconnect) first wait
/// `settleDelay` so the network and login-item retries finish, then run every
/// job whose slot passed while Nimbus was quit or asleep. Other re-plans (job
/// edits, a finished run, clock or time-zone changes) re-arm the timer at once.
@MainActor
final class BackupScheduler {
    /// A due job whose slot is further past than this runs as a catch-up.
    static let catchUpThreshold: TimeInterval = 5 * 60

    private let store: BackupStore
    private let launcher: any BackupLaunching
    private let planner: BackupSchedulePlanner
    private let clock: any Clock<Duration>
    private let now: () -> Date
    private let settleDelay: Duration
    private let busy: @MainActor () -> Set<UUID>
    private let workspaceCenter: NotificationCenter
    private let systemCenter: NotificationCenter

    private var isStarted = false
    private var timer: Task<Void, Never>?
    /// When the pending catch-up pass runs; nothing runs before it.
    private var catchUpAt: Date?
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    init(
        store: BackupStore,
        launcher: any BackupLaunching,
        planner: BackupSchedulePlanner,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping () -> Date = Date.init,
        settleDelay: Duration = .seconds(60),
        busy: @escaping @MainActor () -> Set<UUID>,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        systemCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.launcher = launcher
        self.planner = planner
        self.clock = clock
        self.now = now
        self.settleDelay = settleDelay
        self.busy = busy
        self.workspaceCenter = workspaceCenter
        self.systemCenter = systemCenter
    }

    /// Call once, after the first daemon connect.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter, catchingUp: true)
        observe(.NSSystemClockDidChange, on: systemCenter, catchingUp: false)
        observe(.NSSystemTimeZoneDidChange, on: systemCenter, catchingUp: false)
        replan(catchingUp: true)
    }

    /// Re-arms the timer. `catchingUp` (wake, daemon reconnect) first waits
    /// the settle delay and then runs every due job; otherwise only future
    /// slots are timed. Ignored until `start()`.
    func replan(catchingUp: Bool = false) {
        guard isStarted else { return }
        if catchingUp {
            catchUpAt = now().addingTimeInterval(Self.seconds(settleDelay))
        }
        timer?.cancel()
        timer = Task { [weak self] in await self?.runTimer() }
    }

    func stop() {
        isStarted = false
        timer?.cancel()
        timer = nil
        catchUpAt = nil
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
    }

    private func runTimer() async {
        while !Task.isCancelled {
            guard let target = catchUpAt ?? planner.nextWake(store.jobs, now: now()) else { return }
            let delay = target.timeIntervalSince(now())
            if delay > 0 {
                do {
                    try await clock.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
            // A re-plan may land between the clock firing and this task
            // resuming; its timer owns `catchUpAt` now.
            guard !Task.isCancelled else { return }
            catchUpAt = nil
            // A re-plan during this pass (a run recorded, say) cancels this
            // task; the pass still finishes, because the new timer only
            // times future slots.
            await enqueueDueJobs()
        }
    }

    private func enqueueDueJobs() async {
        let current = now()
        for jobID in planner.dueJobs(store.jobs, now: current, busy: busy()) {
            guard let job = store.job(id: jobID), let slot = planner.nextRun(for: job) else { continue }
            let trigger: BackupRunSummary.Trigger =
                current.timeIntervalSince(slot) > Self.catchUpThreshold ? .catchUp : .scheduled
            await launcher.enqueue(jobID, trigger: trigger)
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, catchingUp: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.replan(catchingUp: catchingUp) }
        }
        observers.append((center, token))
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
