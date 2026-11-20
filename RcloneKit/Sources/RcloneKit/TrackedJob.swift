import Foundation

/// `job/status` for a job waited on with `runJobAndWait`: only what waiting
/// needs. `Job` requires every field rclone reports.
struct JobStatusReply: Decodable, Sendable {
    let finished: Bool
    let success: Bool?
    let error: String?
}

enum TrackedJob {
    /// The first wait between two looks at a job. Quick jobs finish inside
    /// it; the wait then doubles up to the caller's poll interval.
    static let firstPoll: Duration = .milliseconds(50)

    /// The HTTP-style status for a failed job, which has only rclone's
    /// error text. A missing source or target is told apart because callers
    /// treat it differently (the File Provider extension drops the item).
    static func status(forJobError message: String) -> Int {
        message.contains("object not found") || message.contains("directory not found") ? 404 : 500
    }
}

extension RcloneClient {
    /// Starts `endpoint` as an rclone job (`_async: true` added to `params`)
    /// and returns once it has finished.
    ///
    /// A synchronous RC call runs under the HTTP request's context, so when
    /// the client request times out rclone cancels the operation partway. An
    /// `_async` job runs detached from the request and can be polled until
    /// completion or explicitly stopped with `job/stop` on cancellation or
    /// failure.
    public func runJobAndWait(
        _ endpoint: String,
        params: [String: any Sendable],
        pollInterval: Duration = .milliseconds(500),
        onProgress: (@Sendable (StatsResponse) -> Void)? = nil
    ) async throws {
        var asyncParams = params
        asyncParams["_async"] = true
        let started: AsyncJobResponse = try await call(endpoint, params: asyncParams)
        let jobID = started.jobid
        let status: JobStatusReply
        do {
            status = try await waitForJob(jobID, pollInterval: pollInterval, onProgress: onProgress)
        } catch {
            // Detached: the calling task may already be cancelled, and this
            // request has to go out anyway.
            await Task.detached { [self] in try? await self.stopJob(id: jobID) }.value
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw error
        }
        let message = status.error ?? ""
        if status.success == false || !message.isEmpty {
            throw RcloneError.requestFailed(
                status: TrackedJob.status(forJobError: message),
                message: message.isEmpty ? "Job failed" : message
            )
        }
    }

    private func waitForJob(
        _ jobID: Int,
        pollInterval: Duration,
        onProgress: (@Sendable (StatsResponse) -> Void)?
    ) async throws -> JobStatusReply {
        var wait = min(TrackedJob.firstPoll, pollInterval)
        var transportFailures = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: wait)
            wait = min(wait * 2, pollInterval)
            let status: JobStatusReply
            do {
                status = try await call("job/status", params: ["jobid": jobID])
                transportFailures = 0
            } catch let error as URLError where error.code != .cancelled {
                transportFailures += 1
                guard transportFailures < 3 else { throw error }
                continue
            } catch RcloneError.requestFailed(_, let message) where message.contains("job not found") {
                throw RcloneJobLostError(jobID: jobID)
            }
            if status.finished { return status }
            if let onProgress, let stats = try? await getStats(group: "job/\(jobID)") {
                onProgress(stats)
            }
        }
    }

    /// Copies one file as an rclone job and returns once the job has finished.
    ///
    /// Unlike `downloadFile` and `uploadFile`, the bytes never pass through
    /// the caller: rclone reads and writes both ends itself. Given a local
    /// folder as `srcFs` it knows the size up front, so a backend without
    /// streaming uploads (OneDrive) uploads directly instead of first
    /// spooling the stream to a temporary file. Given one as `dstFs` it
    /// downloads a large file over several connections. No request stays
    /// open for the length of the transfer, so the session's resource
    /// timeout doesn't cap it.
    ///
    /// `onProgress` gets the bytes transferred so far each time the job is
    /// looked at. A wait that fails or is cancelled stops the job, so a retry
    /// never runs beside its predecessor; cancelling the calling task throws
    /// `CancellationError`.
    public func copyFileAndWait(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        pollInterval: Duration = .milliseconds(500),
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        let progress: (@Sendable (StatsResponse) -> Void)? = if let onProgress {
            { stats in onProgress(stats.bytes) }
        } else {
            nil
        }
        try await runJobAndWait(
            "operations/copyfile",
            params: [
                "srcFs": srcFs,
                "srcRemote": srcRemote,
                "dstFs": dstFs,
                "dstRemote": dstRemote,
            ],
            pollInterval: pollInterval,
            onProgress: progress
        )
    }

    /// Moves one file (`operations/movefile`) as an rclone job and returns
    /// once it has finished.
    public func moveFileAndWait(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        pollInterval: Duration = .milliseconds(500),
        onProgress: (@Sendable (StatsResponse) -> Void)? = nil
    ) async throws {
        try await runJobAndWait(
            "operations/movefile",
            params: [
                "srcFs": srcFs,
                "srcRemote": srcRemote,
                "dstFs": dstFs,
                "dstRemote": dstRemote,
            ],
            pollInterval: pollInterval,
            onProgress: onProgress
        )
    }

    /// Moves a directory (`sync/move` with `deleteEmptySrcDirs: true`) as an
    /// rclone job. rclone's `MoveDir` uses a server-side directory move when
    /// the backend has one, falling back to per-file server-side moves or
    /// copies.
    public func moveDirectoryAndWait(
        srcFs: String,
        dstFs: String,
        pollInterval: Duration = .milliseconds(500),
        onProgress: (@Sendable (StatsResponse) -> Void)? = nil
    ) async throws {
        try await runJobAndWait(
            "sync/move",
            params: [
                "srcFs": srcFs,
                "dstFs": dstFs,
                "deleteEmptySrcDirs": true,
            ],
            pollInterval: pollInterval,
            onProgress: onProgress
        )
    }

    /// Purges a directory (`operations/purge`) as an rclone job and returns
    /// once it has finished.
    public func purgeAndWait(
        fs: String,
        remote: String,
        pollInterval: Duration = .milliseconds(500),
        onProgress: (@Sendable (StatsResponse) -> Void)? = nil
    ) async throws {
        try await runJobAndWait(
            "operations/purge",
            params: [
                "fs": fs,
                "remote": remote,
            ],
            pollInterval: pollInterval,
            onProgress: onProgress
        )
    }
}
