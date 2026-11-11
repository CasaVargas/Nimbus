import Foundation

/// Finding files by name inside one remote: a recursive `operations/list`
/// run as an rclone job, so it can be stopped on the daemon, not just
/// abandoned on the client.
///
/// rclone's filter only applies to files; folders are always listed. The
/// client therefore checks every name again, which also drops folders whose
/// name doesn't match.
public enum RemoteSearch {
    /// Default recursion cap below the remote root.
    public static let defaultMaxDepth = 10

    /// An rclone include rule that keeps names containing `query`, ignoring
    /// case, at any depth. The query is regex-escaped, so `.` or `(` in a
    /// file name are matched literally.
    public static func includeRule(for query: String) -> String {
        "*{{(?i)\(NSRegularExpression.escapedPattern(for: query))}}*"
    }

    /// Whether `name` contains `query`, ignoring case. Mirrors `includeRule`.
    public static func matches(name: String, query: String) -> Bool {
        name.range(of: query, options: .caseInsensitive) != nil
    }

    /// The `operations/list` body that starts a search job.
    public static func parameters(fs: String, query: String, maxDepth: Int) -> [String: any Sendable] {
        [
            "fs": fs,
            "remote": "",
            "opt": ["recurse": true] as [String: any Sendable],
            "_filter": ["IncludeRule": [includeRule(for: query)]] as [String: any Sendable],
            // `_filter.MaxDepth` is ignored by rclone; depth lives in config.
            "_config": ["MaxDepth": maxDepth] as [String: any Sendable],
            "_async": true,
        ]
    }
}

/// `job/status` for an `operations/list` job. `Job` decodes `output` as a
/// sync report, so the listing needs its own shape.
struct ListJobStatus: Decodable, Sendable {
    let finished: Bool
    let success: Bool?
    let error: String?
    let output: ListResponse?
}

extension RcloneClient {
    /// Files and folders in `fs` whose name contains `query` (case-insensitive),
    /// at most `maxDepth` levels down. Paths are relative to the remote root.
    ///
    /// Cancelling the calling task stops the rclone job and throws
    /// `CancellationError`.
    public func search(
        fs: String,
        query: String,
        maxDepth: Int = RemoteSearch.defaultMaxDepth,
        pollInterval: Duration = .milliseconds(300)
    ) async throws -> [FileItem] {
        let started: AsyncJobResponse = try await call(
            "operations/list",
            params: RemoteSearch.parameters(fs: fs, query: query, maxDepth: maxDepth)
        )
        let jobID = started.jobid

        do {
            while true {
                try Task.checkCancellation()
                let status: ListJobStatus = try await call("job/status", params: ["jobid": jobID])
                if status.finished {
                    if status.success == false || !(status.error ?? "").isEmpty {
                        throw RcloneError.requestFailed(status: 500, message: status.error ?? "Search failed")
                    }
                    return (status.output?.list ?? []).filter {
                        RemoteSearch.matches(name: $0.name, query: query)
                    }
                }
                try await Task.sleep(for: pollInterval)
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // Detached: the calling task is already cancelled, and this
                // request has to go out anyway.
                await Task.detached { [self] in try? await self.stopJob(id: jobID) }.value
                throw CancellationError()
            }
            throw error
        }
    }
}
