import Foundation
import Observation
import RcloneKit
import os

enum TransferOperation: String, Codable, Sendable {
    case copy
    case sync
    case move
}

enum TransferStatus {
    case active
    case completed
    case failed(String)
    case cancelled
}

extension TransferStatus {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

/// Distinguishes how a transfer was initiated so the UI can group / label
/// activity sensibly (manual single-file copies, cross-remote drops from
/// the browser, or batched copy/sync jobs from the Copy/Sync screen).
enum TransferOrigin: String, Codable, Sendable {
    case manual
    case crossRemoteDrop
    case copySyncJob
    /// A run of a saved backup (`BackupRunner`).
    case backup
}

extension Transfer {
    /// True when `remote` is the source or destination fs of this transfer.
    /// Matches on the `"<remote>:"` prefix so "Drive" never claims "Drive2:".
    func involves(remote: String) -> Bool {
        let prefix = "\(remote):"
        return srcFs.hasPrefix(prefix) || dstFs.hasPrefix(prefix)
    }
}

struct Transfer: Identifiable {
    /// What a backup run needs to build its summary when rclone finishes.
    struct BackupContext: Equatable, Sendable {
        let backupID: UUID
        /// The job's name at run time, so history survives a rename or delete.
        let title: String
        let trigger: BackupRunSummary.Trigger
        /// Mirror with versions: removals are moves into the versions folder.
        let isMirrorWithVersions: Bool
        /// The run had `MaxDelete`, so "failed to delete" means the limit hit.
        let hadRemovalLimit: Bool
    }

    var id: UUID { nimbusUUID }
    /// rclone's ID is transient and must never identify a Nimbus row.
    let jobID: Int?
    let operation: TransferOperation
    let srcFs: String
    let dstFs: String
    let startedAt: Date
    var completedAt: Date?
    var status: TransferStatus
    let origin: TransferOrigin
    let nimbusUUID: UUID
    var progress: Double = 0.0
    /// Live throughput in bytes/sec from the last stats poll; nil when idle.
    var speed: Int64?
    /// Estimated seconds remaining, derived from speed + remaining bytes.
    var eta: TimeInterval?
    var backup: BackupContext?
    /// Set when a backup run finishes.
    var summary: BackupRunSummary?

    init(
        jobID: Int?,
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        startedAt: Date,
        completedAt: Date? = nil,
        status: TransferStatus,
        origin: TransferOrigin,
        nimbusUUID: UUID,
        progress: Double = 0.0,
        speed: Int64? = nil,
        eta: TimeInterval? = nil,
        backup: BackupContext? = nil,
        summary: BackupRunSummary? = nil
    ) {
        self.jobID = jobID
        self.operation = operation
        self.srcFs = srcFs
        self.dstFs = dstFs
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.origin = origin
        self.nimbusUUID = nimbusUUID
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.backup = backup
        self.summary = summary
    }

    init(record: TransferRecord) {
        self.init(
            jobID: record.jobID,
            operation: record.operation,
            srcFs: record.source,
            dstFs: record.destination,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            status: .init(outcome: record.outcome),
            origin: record.origin,
            nimbusUUID: record.id,
            progress: record.outcome == .completed ? 1.0 : 0.0,
            backup: record.backupID.map {
                BackupContext(
                    backupID: $0,
                    title: record.title ?? "",
                    trigger: record.summary?.trigger ?? .manual,
                    isMirrorWithVersions: false,
                    hadRemovalLimit: false
                )
            },
            summary: record.summary
        )
    }

    var record: TransferRecord? {
        guard let completedAt else { return nil }
        let outcome: TransferOutcome
        switch status {
        case .active:
            return nil
        case .completed:
            outcome = .completed
        case .failed(let error):
            outcome = .failed(error)
        case .cancelled:
            outcome = .cancelled
        }
        return TransferRecord(
            id: id,
            jobID: jobID,
            operation: operation,
            source: srcFs,
            destination: dstFs,
            startedAt: startedAt,
            completedAt: completedAt,
            outcome: outcome,
            origin: origin,
            backupID: backup?.backupID,
            title: backup?.title,
            summary: summary
        )
    }
}

private extension TransferStatus {
    init(outcome: TransferOutcome) {
        switch outcome {
        case .completed: self = .completed
        case .failed(let error): self = .failed(error)
        case .cancelled: self = .cancelled
        }
    }
}

@Observable
@MainActor
final class TransferStore {
    private(set) var transfers: [Transfer] = []
    private var pollingTask: Task<Void, Never>?
    private let history: any TransferHistoryPersisting
    private let historyWriter: TransferHistoryWriter
    private var retention: TransferHistoryRetention
    private let notifications: any TransferNotifying
    private var notificationMode: TransferNotificationMode
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "transfer-store")
    /// Called once per finished backup run (completed, failed, limit hit or
    /// cancelled). `BackupRunner` records `lastRun` and starts the next job.
    @ObservationIgnored var onBackupFinished: (@MainActor (UUID, BackupRunSummary) async -> Void)?

    init(
        history: any TransferHistoryPersisting = TransferHistoryFile(),
        retention: TransferHistoryRetention = .sevenDays,
        notifications: any TransferNotifying = NoopTransferNotifier(),
        notificationMode: TransferNotificationMode = .failuresOnly
    ) {
        self.history = history
        historyWriter = TransferHistoryWriter(history: history)
        self.retention = retention
        self.notifications = notifications
        self.notificationMode = notificationMode
    }

    var activeTransfers: [Transfer] {
        transfers.filter {
            if case .active = $0.status { return true }
            return false
        }
    }

    var completedTransfers: [Transfer] {
        transfers.filter {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
    }

    func addTransfer(
        jobId: Int,
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        origin: TransferOrigin = .manual,
        nimbusUUID: UUID = UUID(),
        backup: Transfer.BackupContext? = nil
    ) {
        let transfer = Transfer(
            jobID: jobId,
            operation: operation,
            srcFs: srcFs,
            dstFs: dstFs,
            startedAt: Date(),
            status: .active,
            origin: origin,
            nimbusUUID: nimbusUUID,
            backup: backup
        )
        transfers.append(transfer)
    }

    /// Updates the progress for an in-flight transfer. Clamped to `0...1`.
    func setProgress(_ progress: Double, forJobId jobID: Int) {
        guard let idx = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobID }) else { return }
        transfers[idx].progress = max(0, min(1, progress))
    }

    func completeTransfer(jobId: Int) async {
        if let index = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobId }) {
            transfers[index].status = .completed
            transfers[index].completedAt = Date()
            if let record = transfers[index].record {
                await notifications.deliver(record, mode: notificationMode)
            }
            await persistRetainedHistory()
        }
    }

    func failTransfer(jobId: Int, error: String) async {
        if let index = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobId }) {
            transfers[index].status = .failed(error)
            transfers[index].completedAt = Date()
            if let record = transfers[index].record {
                await notifications.deliver(record, mode: notificationMode)
            }
            await persistRetainedHistory()
        }
    }

    func cancelTransfer(jobId: Int) async {
        if let index = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobId }) {
            let now = Date()
            transfers[index].status = .cancelled
            transfers[index].completedAt = now
            let finished = attachBackupSummary(at: index, outcome: .cancelled, stats: nil, now: now)
            await persistRetainedHistory()
            await notifyBackupFinished(finished)
        }
    }

    /// Applies a finished rclone job to its transfer. For a backup run it
    /// also builds the run summary from `stats` and calls `onBackupFinished`.
    func handleFinished(jobID: Int, job: Job, stats: StatsResponse?, now: Date = Date()) async {
        guard let index = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobID }) else { return }
        if job.success { transfers[index].progress = 1.0 }
        let outcome: BackupRunSummary.Outcome = job.success
            ? .completed
            : Self.backupOutcome(jobError: job.error, hadRemovalLimit: transfers[index].backup?.hadRemovalLimit ?? false)
        let finished = attachBackupSummary(at: index, outcome: outcome, stats: stats, now: now)
        transfers[index].status = job.success ? .completed : .failed(job.error)
        transfers[index].completedAt = now
        if let record = transfers[index].record {
            await notifications.deliver(record, mode: notificationMode)
        }
        await persistRetainedHistory()
        await notifyBackupFinished(finished)
    }

    /// rclone ends a run stopped by `MaxDelete` with "failed to delete N
    /// files". Only a run that set a limit can have hit it.
    static func backupOutcome(jobError: String, hadRemovalLimit: Bool) -> BackupRunSummary.Outcome {
        if hadRemovalLimit, jobError.contains("failed to delete") { return .limitHit }
        return .failed(jobError)
    }

    /// rclone's stats don't split new from changed files, so a real run
    /// reports everything as copied. With versions, a removal is a move.
    static func summary(
        trigger: BackupRunSummary.Trigger,
        startedAt: Date,
        finishedAt: Date,
        outcome: BackupRunSummary.Outcome,
        stats: StatsResponse?,
        isMirrorWithVersions: Bool
    ) -> BackupRunSummary {
        let removed = isMirrorWithVersions
            ? (stats?.deletes ?? 0) + (stats?.renames ?? 0)
            : (stats?.deletes ?? 0)
        return BackupRunSummary(
            startedAt: startedAt,
            finishedAt: finishedAt,
            trigger: trigger,
            outcome: outcome,
            copied: stats?.transfers ?? 0,
            replaced: 0,
            removed: removed,
            errors: stats?.errors ?? 0,
            bytes: stats?.bytes ?? 0
        )
    }

    private func attachBackupSummary(
        at index: Int,
        outcome: BackupRunSummary.Outcome,
        stats: StatsResponse?,
        now: Date
    ) -> (UUID, BackupRunSummary)? {
        guard let backup = transfers[index].backup else { return nil }
        let summary = Self.summary(
            trigger: backup.trigger,
            startedAt: transfers[index].startedAt,
            finishedAt: now,
            outcome: outcome,
            stats: stats,
            isMirrorWithVersions: backup.isMirrorWithVersions
        )
        transfers[index].summary = summary
        return (backup.backupID, summary)
    }

    private func notifyBackupFinished(_ finished: (UUID, BackupRunSummary)?) async {
        guard let (id, summary) = finished, let onBackupFinished else { return }
        await onBackupFinished(id, summary)
    }

    /// Stops the rclone job, then marks the transfer cancelled. A stop
    /// failure (job already finished/cleaned up) still cancels locally —
    /// the poll loop would have flipped it to completed/failed anyway.
    func stop(jobId: Int, client: RcloneClient) async {
        try? await client.stopJob(id: jobId)
        await cancelTransfer(jobId: jobId)
    }

    /// Removes one finished transfer from the list (row-level counterpart
    /// of `clearCompleted`). Active transfers are not removable.
    func remove(id: UUID) async {
        transfers.removeAll { $0.id == id && !$0.status.isActive }
        await persistRetainedHistory()
    }

    func clearCompleted() async {
        transfers.removeAll {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
        await persistRetainedHistory()
    }

    func restoreHistory(retention: TransferHistoryRetention) async {
        self.retention = retention
        guard retention != .untilQuit else { return }

        do {
            let loaded = try await history.load()
            let retained = TransferHistoryPolicy.prune(loaded, retention: retention)
            let liveIDs = Set(transfers.map(\.id))
            transfers.append(contentsOf: retained.lazy.filter { !liveIDs.contains($0.id) }.map(Transfer.init(record:)))
            if retained != loaded {
                await save(records: retained)
            }
        } catch TransferHistoryFileError.corrupt {
            logger.error("Transfer history is corrupt; quarantining the file")
            await history.quarantineCorruptFile()
        } catch TransferHistoryFileError.unsupportedVersion(let version) {
            logger.error("Transfer history version \(version) is unsupported; preserving the file")
        } catch {
            logger.error("Unable to restore transfer history: \(error.localizedDescription)")
        }
    }

    func applyRetention(_ retention: TransferHistoryRetention) async {
        self.retention = retention
        guard retention != .untilQuit else { return }
        await persistRetainedHistory()
    }

    /// App-facing settings boundary so retention changes take effect without
    /// waiting for the next process launch.
    func applyRetention(from settings: AppSettings) async {
        await applyRetention(settings.transferHistoryRetention)
    }

    func applyNotificationMode(_ notificationMode: TransferNotificationMode) {
        self.notificationMode = notificationMode
    }

    func applyNotificationMode(from settings: AppSettings) {
        applyNotificationMode(settings.transferNotificationMode)
    }

    func startPolling(client: RcloneClient) {
        pollingTask = Task {
            while !Task.isCancelled {
                // ~4fps poll cadence keeps progress rings smooth without
                // hammering the rclone RC API. Phase 1 acceptable; revisit
                // if CPU pressure shows up in profiling.
                try? await Task.sleep(for: .milliseconds(250))
                await self.pollActiveJobs(client: client)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollActiveJobs(client: RcloneClient) async {
        for transfer in activeTransfers {
            guard let jobID = transfer.jobID else {
                logger.error("Active transfer \(transfer.id) has no rclone job ID")
                continue
            }
            do {
                let job = try await client.jobStatus(id: jobID)

                // Update progress from per-group stats while the job is still
                // running. `try?` keeps a transient stats failure non-fatal —
                // we'll retry on the next poll cycle.
                if !job.finished, !job.group.isEmpty {
                    if let stats = try? await client.getStats(group: job.group) {
                        let progress = computeProgress(from: stats)
                        setProgress(progress, forJobId: jobID)
                        updateRates(from: stats, forJobId: jobID)
                    }
                }

                if job.finished {
                    // A backup's summary needs the job's final counts; read
                    // them once before rclone expires the stats group.
                    let stats = transfer.backup == nil ? nil : try? await client.getStats(group: job.group)
                    await handleFinished(jobID: jobID, job: job, stats: stats)
                }
            } catch {
                // Job may have been cleaned up by rclone — expected for old jobs.
                // Transient errors will cause retries on the next poll cycle.
                logger.debug("Job \(jobID) status poll failed (may be cleaned up): \(error)")
            }
        }
    }

    /// Publishes throughput + derived ETA for the row caption. rclone's
    /// top-level stats carry `speed` but no aggregate ETA, so we derive it
    /// from remaining bytes whenever bytes accounting is live.
    private func updateRates(from stats: StatsResponse, forJobId jobID: Int) {
        guard let idx = transfers.firstIndex(where: { $0.status.isActive && $0.jobID == jobID }) else { return }
        let speed = Int64(stats.speed)
        transfers[idx].speed = speed > 0 ? speed : nil
        if speed > 0, stats.totalBytes > 0, stats.bytes <= stats.totalBytes {
            transfers[idx].eta = TimeInterval(stats.totalBytes - stats.bytes) / TimeInterval(speed)
        } else {
            transfers[idx].eta = nil
        }
    }

    /// Computes overall progress from a `StatsResponse`:
    /// - prefers `totalBytes` / `bytes` when `totalBytes > 0`
    /// - falls back to averaging `transferring[].percentage` when bytes
    ///   accounting is missing (small files, multi-file batches early on)
    private func computeProgress(from stats: StatsResponse) -> Double {
        if stats.totalBytes > 0 {
            return max(0, min(1, Double(stats.bytes) / Double(stats.totalBytes)))
        }
        guard let transferring = stats.transferring, !transferring.isEmpty else { return 0 }
        let avg = Double(transferring.map(\.percentage).reduce(0, +)) / Double(transferring.count)
        return max(0, min(1, avg / 100.0))
    }

    private func persistRetainedHistory() async {
        guard retention != .untilQuit else { return }
        let retained = TransferHistoryPolicy.prune(transfers.compactMap(\.record), retention: retention)
        let retainedIDs = Set(retained.map(\.id))
        transfers.removeAll { !$0.status.isActive && !retainedIDs.contains($0.id) }
        await save(records: retained)
    }

    private func save(records: [TransferRecord]) async {
        do {
            try await historyWriter.save(records)
        } catch {
            logger.error("Unable to save transfer history: \(error.localizedDescription)")
        }
    }
}
