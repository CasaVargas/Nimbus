import Foundation

/// `job/status` for an `operations/copyfile` job: only what waiting on it
/// needs. `Job` requires every field rclone reports.
struct CopyJobStatus: Decodable, Sendable {
    let finished: Bool
    let success: Bool?
    let error: String?
}

enum TrackedCopy {
    /// The first wait between two looks at a job. Small files finish inside
    /// it; the wait then doubles up to the caller's poll interval.
    static let firstPoll: Duration = .milliseconds(50)

    /// The HTTP-style status for a failed copy job, which has only rclone's
    /// error text. A missing source is told apart because callers treat it
    /// differently (the File Provider extension drops the item).
    static func status(forJobError message: String) -> Int {
        message.contains("object not found") || message.contains("directory not found") ? 404 : 500
    }
}

extension RcloneClient {
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
        let jobID = try await copyFileAsync(
            srcFs: srcFs, srcRemote: srcRemote, dstFs: dstFs, dstRemote: dstRemote
        )
        let status: CopyJobStatus
        do {
            status = try await waitForCopyJob(jobID, pollInterval: pollInterval, onProgress: onProgress)
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
                status: TrackedCopy.status(forJobError: message),
                message: message.isEmpty ? "Transfer failed" : message
            )
        }
    }

    private func waitForCopyJob(
        _ jobID: Int,
        pollInterval: Duration,
        onProgress: (@Sendable (Int64) -> Void)?
    ) async throws -> CopyJobStatus {
        var wait = min(TrackedCopy.firstPoll, pollInterval)
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: wait)
            let status: CopyJobStatus = try await call("job/status", params: ["jobid": jobID])
            if status.finished { return status }
            if let onProgress, let stats = try? await getStats(group: "job/\(jobID)") {
                onProgress(stats.bytes)
            }
            wait = min(wait * 2, pollInterval)
        }
    }
}
