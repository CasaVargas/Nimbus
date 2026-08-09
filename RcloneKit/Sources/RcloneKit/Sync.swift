import Foundation

extension RcloneClient {
    public func copy(srcFs: String, dstFs: String, extraParams: [String: String] = [:]) async throws -> Int {
        var params: [String: any Sendable] = [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ]
        for (key, value) in extraParams { params[key] = value }
        let response: AsyncJobResponse = try await call("sync/copy", params: params)
        return response.jobid
    }

    public func sync(srcFs: String, dstFs: String) async throws -> Int {
        let response: AsyncJobResponse = try await call("sync/sync", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ])
        return response.jobid
    }

    /// Moves the entire contents of `srcFs` into `dstFs`, deleting the emptied
    /// source directories afterward. rclone has no RC endpoint for renaming a
    /// directory as a single atomic unit — `operations/movefile` only moves
    /// individual files — so directory renames/moves go through `sync/move`
    /// with both `srcFs`/`dstFs` set to the *directory* paths themselves,
    /// mirroring the `rclone move <src-dir> <dst-dir>` CLI command. Runs
    /// synchronously (no `_async`) so the caller only sees success once the
    /// move has actually completed.
    public func moveDirectory(srcFs: String, dstFs: String) async throws {
        try await call("sync/move", params: [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "deleteEmptySrcDirs": true,
        ])
    }
}
