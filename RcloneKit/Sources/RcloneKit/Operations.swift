import Foundation

extension RcloneClient {
    public func listFiles(fs: String, remote: String) async throws -> [FileItem] {
        let response: ListResponse = try await call("operations/list", params: [
            "fs": fs,
            "remote": remote,
        ])
        return response.list
    }

    public func stat(fs: String, remote: String) async throws -> FileItem {
        let response: StatResponse = try await call("operations/stat", params: [
            "fs": fs,
            "remote": remote,
        ])
        return response.item
    }

    public func mkdir(fs: String, remote: String) async throws {
        try await call("operations/mkdir", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    public func deleteFile(fs: String, remote: String) async throws {
        try await call("operations/deletefile", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    public func purge(fs: String, remote: String) async throws {
        try await call("operations/purge", params: [
            "fs": fs,
            "remote": remote,
        ])
    }

    public func moveFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws {
        try await call("operations/movefile", params: [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
        ])
    }

    public func copyFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws {
        try await call("operations/copyfile", params: [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
        ])
    }

    /// Asynchronously copy a single file. Returns the rclone job ID.
    /// Same endpoint as `copyFile` but with `_async: true` so the caller can track progress.
    public func copyFileAsync(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        extraParams: [String: String] = [:]
    ) async throws -> Int {
        var params: [String: any Sendable] = [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
            "_async": true,
        ]
        for (key, value) in extraParams {
            params[key] = value
        }
        let response: AsyncJobResponse = try await call("operations/copyfile", params: params)
        return response.jobid
    }

    /// Asynchronously move a single file. Returns the rclone job ID.
    public func moveFileAsync(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        extraParams: [String: String] = [:]
    ) async throws -> Int {
        var params: [String: any Sendable] = [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
            "_async": true,
        ]
        for (key, value) in extraParams {
            params[key] = value
        }
        let response: AsyncJobResponse = try await call("operations/movefile", params: params)
        return response.jobid
    }

    public func about(fs: String) async throws -> AboutResponse {
        try await call("operations/about", params: ["fs": fs])
    }
}
