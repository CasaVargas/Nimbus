import Foundation
import Observation
import RcloneKit

/// What a backup (or a one-off copy) would do, from an rclone dry run.
struct BackupPreview: Equatable, Sendable {
    let willCopy: [String]
    let willReplace: [String]
    let willRemove: [String]
    let errors: [String]
    /// rclone's `totalBytes` for the dry run; includes moves into versions.
    let approxBytes: Int64
    /// The dry run reported that the removal limit would stop the run.
    let limitHit: Bool
    let removalLimit: Int?
    /// The job's fingerprint when the preview ran; approval stores this.
    let fingerprint: String
    let finishedAt: Date

    var isEmpty: Bool {
        willCopy.isEmpty && willReplace.isEmpty && willRemove.isEmpty && errors.isEmpty
    }

    /// A preview that hits the removal limit can't be approved: the real
    /// run would stop at the same limit. The user raises or turns off the
    /// limit in Edit first.
    var canApprove: Bool { errors.isEmpty && !limitHit }

    static let largeRemovalThreshold = 100

    /// More removals than this need a second confirmation naming the count.
    var needsRemovalConfirmation: Bool {
        !limitHit && willRemove.count > Self.largeRemovalThreshold
    }
}

/// Runs a dry run and turns its report into a `BackupPreview`. One
/// previewer per preview sheet; cancelling stops the rclone job.
@Observable
@MainActor
final class BackupPreviewer {
    enum State: Equatable, Sendable {
        case idle
        case checking(listed: Int)
        case finished(BackupPreview)
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let client: any BackupRcloneClient
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var runningJobID: Int?
    @ObservationIgnored private var cancelled = false

    init(
        client: any BackupRcloneClient,
        pollInterval: Duration = .milliseconds(250),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.pollInterval = pollInterval
        self.now = now
    }

    func run(job: BackupJob) async {
        let request = BackupRequest.make(job: job, dryRun: true, stamp: BackupRequest.stamp(for: now()))
        await run(request: request, fingerprint: job.fingerprint,
                  removalLimit: job.mode == .mirror ? job.removalLimit : nil)
    }

    /// Previews any sync/copy request. `request.dryRun` is forced on.
    func run(request: SyncRequest, fingerprint: String, removalLimit: Int?) async {
        var request = request
        request.dryRun = true
        if request.reports.isEmpty {
            request.reports = [.missingOnDst, .differ, .error]
            if request.operation == .sync { request.reports.insert(.missingOnSrc) }
        }
        cancelled = false
        state = .checking(listed: 0)

        let jobID: Int
        do {
            jobID = try await client.startSync(request)
        } catch {
            state = .failed(BackupErrorText.friendly(NimbusError.classify(error).message))
            return
        }
        runningJobID = jobID
        defer { runningJobID = nil }

        while true {
            // cancel() already stopped the job; a cancelled task (the sheet
            // went away) stops it here.
            if cancelled { return }
            if Task.isCancelled {
                await stop(jobID)
                return
            }
            let job: Job
            do {
                job = try await client.jobStatus(id: jobID)
            } catch {
                state = .failed(BackupErrorText.friendly(NimbusError.classify(error).message))
                return
            }
            // cancel() already stopped the job; a cancelled task (the sheet
            // went away) stops it here.
            if cancelled { return }
            if Task.isCancelled {
                await stop(jobID)
                return
            }
            let stats = try? await client.getStats(group: job.group)
            guard job.finished else {
                state = .checking(listed: stats?.listed ?? 0)
                try? await Task.sleep(for: pollInterval)
                continue
            }
            finish(job: job, stats: stats, fingerprint: fingerprint,
                   removalLimit: removalLimit, isMirror: request.operation == .sync)
            return
        }
    }

    /// Stops a dry run that is still checking.
    func cancel() async {
        guard case .checking = state else { return }
        cancelled = true
        if let runningJobID { await stop(runningJobID) }
    }

    private func stop(_ jobID: Int) async {
        try? await client.stopJob(id: jobID)
        runningJobID = nil
        state = .idle
    }

    private func finish(job: Job, stats: StatsResponse?, fingerprint: String, removalLimit: Int?, isMirror: Bool) {
        let limitHit = !job.success
            && TransferStore.backupOutcome(jobError: job.error, hadRemovalLimit: removalLimit != nil) == .limitHit
        guard job.success || limitHit else {
            state = .failed(BackupErrorText.friendly(job.error))
            return
        }
        let report = job.output
        state = .finished(BackupPreview(
            willCopy: report?.missingOnDst ?? [],
            willReplace: report?.differ ?? [],
            willRemove: isMirror ? (report?.missingOnSrc ?? []) : [],
            errors: report?.error ?? [],
            approxBytes: stats?.totalBytes ?? 0,
            limitHit: limitHit,
            removalLimit: removalLimit,
            fingerprint: fingerprint,
            finishedAt: now()
        ))
    }
}
