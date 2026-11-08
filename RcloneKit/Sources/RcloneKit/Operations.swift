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
        // Quota computation is slow on large Google Workspace / shared drives
        // (empirically ~15-20s, longer under concurrent startup load), so the
        // default 30s request timeout is too tight. Give it generous headroom.
        try await call("operations/about", params: ["fs": fs], timeout: 120)
    }

    /// A public link to `remote` (a file or folder) via `operations/publiclink`.
    /// `expire` is an rclone duration ("7d", "1h"); services that don't
    /// support expiry ignore it. `unlink: true` removes an existing link
    /// where the service supports that, and returns no URL.
    @discardableResult
    public func publicLink(fs: String, remote: String, expire: String? = nil, unlink: Bool = false) async throws -> URL? {
        var params: [String: any Sendable] = ["fs": fs, "remote": remote]
        if let expire { params["expire"] = expire }
        if unlink { params["unlink"] = true }
        let response: PublicLinkResponse = try await call("operations/publiclink", params: params, timeout: 60)
        guard let url = response.url, !url.isEmpty else { return nil }
        return URL(string: url)
    }

    /// What this remote's backend can do, from `operations/fsinfo`. Answered
    /// locally by rclone (no network call for most backends).
    public func features(fs: String) async throws -> RemoteFeatures {
        let info: FsInfoResponse = try await call("operations/fsinfo", params: ["fs": fs])
        return RemoteFeatures(publicLink: info.features["PublicLink"] ?? false)
    }
}

/// The subset of a backend's `Features` Nimbus acts on.
public struct RemoteFeatures: Sendable, Equatable, Codable {
    public let publicLink: Bool

    public init(publicLink: Bool) {
        self.publicLink = publicLink
    }
}

private struct PublicLinkResponse: Decodable, Sendable {
    let url: String?
}

private struct FsInfoResponse: Decodable, Sendable {
    let features: [String: Bool]

    enum CodingKeys: String, CodingKey { case features = "Features" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Features mixes booleans with the occasional non-boolean entry in
        // some rclone versions; keep the booleans, ignore the rest.
        let raw = try c.decodeIfPresent([String: LenientBool].self, forKey: .features) ?? [:]
        features = raw.compactMapValues(\.value)
    }
}

private struct LenientBool: Decodable, Sendable {
    let value: Bool?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Bool.self)
    }
}
