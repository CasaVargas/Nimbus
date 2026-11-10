import Foundation
import Observation
import os

/// Anything that can be asked to run a saved backup (the Backups screen
/// today, the scheduler in phase 2).
@MainActor
protocol BackupLaunching: AnyObject {
    func enqueue(_ jobID: UUID, trigger: BackupRunSummary.Trigger) async
}

/// Runs saved backups one at a time on the app's rclone daemon. Each run is
/// a `.backup` transfer in `TransferStore`; when it finishes, the runner
/// records `lastRun` and starts the next queued job.
@Observable
@MainActor
final class BackupRunner: BackupLaunching {
    enum Refusal: Equatable {
        case notApproved
        case alreadyQueuedOrRunning
        case storeReadOnly
        case daemonNotConnected
        case unknownJob
    }

    /// Jobs waiting to start, in order.
    private(set) var queue: [UUID] = []
    private(set) var runningJobID: UUID?
    /// Taken off the queue, its start request not yet answered.
    private(set) var startingJobID: UUID?
    private(set) var lastRefusal: Refusal?

    /// Called when a scheduled run is lost and left unrecorded, so the
    /// scheduler re-plans and catches it up.
    @ObservationIgnored var onRunLost: (@MainActor () -> Void)?
    @ObservationIgnored private var triggers: [UUID: BackupRunSummary.Trigger] = [:]
    /// Jobs whose last scheduled run was lost and left unrecorded so it runs
    /// again. A second loss in a row is recorded, so a run that itself takes
    /// the daemon down can't loop. Cleared when any run of the job is recorded.
    @ObservationIgnored private var retriedAfterLoss: Set<UUID> = []
    @ObservationIgnored private var runningRcloneJob: Int?
    /// Versions prunes in flight, by job.
    @ObservationIgnored private var pruning: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private let store: BackupStore
    @ObservationIgnored private let transfers: TransferStore
    @ObservationIgnored private let client: any BackupRcloneClient
    @ObservationIgnored private let isDaemonConnected: @MainActor () -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let beginActivity: @MainActor (String) -> any NSObjectProtocol
    @ObservationIgnored private let endActivity: @MainActor (any NSObjectProtocol) -> Void
    /// Keeps the Mac from idle-sleeping from the first run until the queue empties.
    @ObservationIgnored private var sleepActivity: (any NSObjectProtocol)?
    @ObservationIgnored private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "backups")

    init(
        store: BackupStore,
        transfers: TransferStore,
        client: any BackupRcloneClient,
        isDaemonConnected: @escaping @MainActor () -> Bool,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { TimeZone.current },
        beginActivity: @escaping @MainActor (String) -> any NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: $0)
        },
        endActivity: @escaping @MainActor (any NSObjectProtocol) -> Void = {
            ProcessInfo.processInfo.endActivity($0)
        }
    ) {
        self.store = store
        self.transfers = transfers
        self.client = client
        self.isDaemonConnected = isDaemonConnected
        self.now = now
        self.timeZone = timeZone
        self.beginActivity = beginActivity
        self.endActivity = endActivity
        transfers.onBackupFinished = { [weak self] id, summary in
            await self?.runFinished(id, summary: summary)
        }
    }

    var isRunningAnything: Bool { !busyJobIDs.isEmpty }

    /// Jobs queued, starting or running: the scheduler's `busy` set.
    var busyJobIDs: Set<UUID> {
        Set(queue).union([startingJobID, runningJobID].compactMap { $0 })
    }

    /// Call after jobs change (the store's `onJobsChanged`). Drops queued
    /// scheduled and catch-up runs of jobs that are now paused; a queued
    /// Back Up Now stays.
    func jobsDidChange() {
        let dropped = queue.filter { id in
            store.job(id: id)?.isPaused == true && triggers[id] != .manual
        }
        guard !dropped.isEmpty else { return }
        queue.removeAll { dropped.contains($0) }
        for id in dropped { triggers[id] = nil }
    }

    func isQueued(_ jobID: UUID) -> Bool { queue.contains(jobID) }

    /// The active transfer of the running job, for progress.
    func activeTransfer(for jobID: UUID) -> Transfer? {
        guard runningJobID == jobID else { return nil }
        return transfers.activeTransfers.first { $0.backup?.backupID == jobID }
    }

    func enqueue(_ jobID: UUID, trigger: BackupRunSummary.Trigger) async {
        if let refusal = refusal(for: jobID) {
            lastRefusal = refusal
            logger.info("Backup \(jobID) not queued: \(String(describing: refusal))")
            return
        }
        lastRefusal = nil
        queue.append(jobID)
        triggers[jobID] = trigger
        await startNextIfIdle()
    }

    /// Stops a running job (the next one starts) or drops a queued one.
    func stop(_ jobID: UUID) async {
        if let index = queue.firstIndex(of: jobID) {
            queue.remove(at: index)
            triggers[jobID] = nil
            return
        }
        guard runningJobID == jobID, let rcloneJob = runningRcloneJob else { return }
        try? await client.stopJob(id: rcloneJob)
        // Cancelling the transfer calls onBackupFinished, which records the
        // run and starts the next job.
        await transfers.cancelTransfer(jobId: rcloneJob)
    }

    private func refusal(for jobID: UUID) -> Refusal? {
        guard store.isWritable else { return .storeReadOnly }
        guard let job = store.job(id: jobID) else { return .unknownJob }
        guard job.isApproved else { return .notApproved }
        guard !busyJobIDs.contains(jobID) else { return .alreadyQueuedOrRunning }
        guard isDaemonConnected() else { return .daemonNotConnected }
        return nil
    }

    private func startNextIfIdle() async {
        guard runningJobID == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        while runningJobID == nil, !queue.isEmpty {
            let jobID = queue.removeFirst()
            let trigger = triggers.removeValue(forKey: jobID) ?? .manual
            // Re-check: the job may have been edited, deleted or paused while
            // queued. Paused jobs don't run on their schedule; Back Up Now does.
            guard let job = store.job(id: jobID), job.isApproved, !(job.isPaused && trigger != .manual) else {
                logger.info("Skipping backup \(jobID): changed, removed or paused while queued")
                continue
            }
            let startedAt = now()
            let request = BackupRequest.make(job: job, dryRun: false, stamp: BackupRequest.stamp(for: startedAt))
            // Busy while the start request is in flight, so it isn't queued twice.
            startingJobID = jobID
            do {
                let rcloneJob = try await client.startSync(request)
                startingJobID = nil
                runningJobID = jobID
                runningRcloneJob = rcloneJob
                if sleepActivity == nil {
                    sleepActivity = beginActivity("Backing up \(job.name)")
                }
                transfers.addTransfer(
                    jobId: rcloneJob,
                    operation: job.mode == .mirror ? .sync : .copy,
                    srcFs: request.srcFs,
                    dstFs: request.dstFs,
                    origin: .backup,
                    backup: Transfer.BackupContext(
                        backupID: jobID,
                        title: job.name,
                        trigger: trigger,
                        isMirrorWithVersions: job.mode == .mirror && job.versions.enabled,
                        hadRemovalLimit: request.maxDelete != nil,
                        removalLimit: request.maxDelete
                    )
                )
            } catch {
                startingJobID = nil
                let message = BackupErrorText.friendly(NimbusError.classify(error).message)
                logger.error("Backup \(jobID) failed to start: \(message)")
                await record(jobID, BackupRunSummary(
                    startedAt: startedAt, finishedAt: now(), trigger: trigger,
                    outcome: .failed(message), copied: 0, replaced: 0, removed: 0, errors: 1, bytes: 0
                ))
            }
        }
        if runningJobID == nil, let activity = sleepActivity {
            endActivity(activity)
            sleepActivity = nil
        }
    }

    private func runFinished(_ jobID: UUID, summary: BackupRunSummary) async {
        var summary = summary
        if case .failed(let raw) = summary.outcome {
            summary.outcome = .failed(BackupErrorText.friendly(raw))
        }
        // Not busy any more before the run is recorded: recording re-plans
        // the scheduler, which must see an overdue next slot as runnable.
        if runningJobID == jobID {
            runningJobID = nil
            runningRcloneJob = nil
        }
        if summary.outcome == .failed(TransferStore.lostRunMessage), summary.trigger != .manual,
           retriedAfterLoss.insert(jobID).inserted {
            // The daemon went away mid-run. Like a run cut off by quit, it
            // counts as missed: no lastRun, so its slot stays due and the
            // reconnect catch-up pass runs it again after the settle delay.
            logger.info("Backup \(jobID) lost with the daemon; it runs again on catch-up")
            onRunLost?()
        } else {
            await record(jobID, summary)
            if summary.outcome == .completed { startPruning(jobID) }
        }
        await startNextIfIdle()
    }

    /// Deletes the job's versions folders past its Keep for, in the
    /// background: a slow listing never holds up the next queued job, and a
    /// failure is only logged. One prune per job at a time.
    ///
    /// A prune is not part of the quit guard (`isRunningAnything`): a
    /// cut-off purge is idempotent, so one cut short by quit is finished by
    /// the next completed run, which lists the folder again.
    private func startPruning(_ jobID: UUID) {
        guard pruning[jobID] == nil, let job = store.job(id: jobID), job.versions.enabled else { return }
        // Other jobs may keep versions in the same folder for longer.
        let keep = VersionsPruner.effectiveKeep(for: job, among: store.jobs)
        guard keep != .forever else { return }
        let client = client
        let now = now()
        let timeZone = timeZone()
        let logger = logger
        let folder = VersionsPruner.versionsFolder(of: job)
        // Edit and Delete stay enabled during a prune, so every purge first
        // checks the job as it is now.
        let mayPurge: VersionsPruner.MayPurge = { [weak self] stamp in
            self?.mayStillPrune(jobID, folder: folder, stamp: stamp, now: now, timeZone: timeZone) ?? false
        }
        pruning[jobID] = Task { [weak self] in
            let outcome = await VersionsPruner.prune(job: job, keep: keep, client: client,
                                                       now: now, timeZone: timeZone, mayPurge: mayPurge)
            switch outcome {
            case .skipped:
                break
            case .noVersionsYet:
                logger.debug("Backup \(jobID): no versions folder yet, nothing to prune")
            case .pruned(let names):
                if !names.isEmpty { logger.info("Backup \(jobID): removed \(names.count) old versions folders") }
            case .stopped(let names):
                logger.info("Backup \(jobID): changed while removing old versions; stopped after \(names.count)")
            case .failed(let message):
                logger.error("Backup \(jobID): couldn't remove old versions: \(message)")
            }
            self?.pruning[jobID] = nil
        }
    }

    /// Whether a prune started with `folder` may still purge `stamp`: the job
    /// still exists with versions on in that same folder, and the stamp is
    /// past the cut-off for the Keep for that applies to the folder now.
    private func mayStillPrune(_ jobID: UUID, folder: VersionsPruner.Location?, stamp: String,
                               now: Date, timeZone: TimeZone) -> Bool {
        guard let job = store.job(id: jobID), job.versions.enabled, let folder,
              VersionsPruner.versionsFolder(of: job) == folder else { return false }
        let keep = VersionsPruner.effectiveKeep(for: job, among: store.jobs)
        return VersionsPruner.isPastCutOff(stamp, keep: keep, now: now, timeZone: timeZone)
    }

    /// Waits for every versions prune started so far. Tests only.
    func waitForPruning() async {
        while let task = pruning.values.first {
            await task.value
        }
    }

    private func record(_ jobID: UUID, _ summary: BackupRunSummary) async {
        retriedAfterLoss.remove(jobID)
        await store.recordRun(id: jobID, summary: summary)
    }
}
