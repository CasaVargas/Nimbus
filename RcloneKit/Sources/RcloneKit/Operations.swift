import Foundation

extension RcloneClient {
    public func listFiles(fs: String, remote: String) async throws -> [FileItem] {
        try await listFiles(fs: fs, remote: remote, timeout: nil)
    }

    /// - Parameter timeout: Overrides the 30s default. A listing the user
    ///   is waiting on passes a longer one: a rate-limited service (Google
    ///   Drive on rclone's shared client ID) answers after rclone's backoff,
    ///   which can run past 30s.
    public func listFiles(fs: String, remote: String, timeout: TimeInterval?) async throws -> [FileItem] {
        let response: ListResponse = try await call("operations/list", params: [
            "fs": fs,
            "remote": remote,
        ], timeout: timeout)
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

    /// Creates a folder the user can then see and open.
    ///
    /// On most services that is `mkdir`. Bucket stores (S3, Backblaze B2,
    /// Google Cloud Storage, Azure Blob) keep no empty folders: inside a
    /// bucket `mkdir` succeeds and creates nothing. There the folder is
    /// made real one of two ways:
    ///
    /// - Where rclone has `directory_markers` (S3, GCS, Azure Blob), that
    ///   option is turned on for the remote and `mkdir` repeated. rclone
    ///   then writes the zero-byte `folder/` object those services' own
    ///   consoles write.
    /// - Anywhere else, or if that left no folder, a zero-byte placeholder file goes into the folder:
    ///   `.bzEmpty` on B2, as Backblaze's web interface does, else `.keep`.
    public func createFolder(fs: String, remote: String) async throws {
        try await mkdir(fs: fs, remote: remote)
        let info: FsInfoResponse = try await call("operations/fsinfo", params: ["fs": fs])
        guard info.features["CanHaveEmptyDirectories"] == false else { return }
        // A new bucket, or a folder that already has files, is there now.
        guard try await !exists(fs: fs, remote: remote) else { return }

        let base = try await baseRemote(ofFs: fs)
        if let base, Self.directoryMarkerBackends.contains(base.type) {
            try await call("config/update", params: [
                "name": base.name,
                "parameters": ["directory_markers": "true"],
                "opt": ["nonInteractive": true],
            ])
            // A crypt or alias over this remote keeps using the copy of it
            // rclone made before the change, until the cache is dropped.
            try await call("fscache/clear")
            try await mkdir(fs: fs, remote: remote)
            if try await exists(fs: fs, remote: remote) { return }
        }
        let placeholder = base?.type == "b2" ? Self.b2FolderPlaceholder : Self.folderPlaceholder
        try await uploadData(Data(), fs: fs, remote: remote, filename: placeholder)
    }

    /// The file Backblaze's web interface puts in a new, empty folder.
    public static let b2FolderPlaceholder = ".bzEmpty"
    /// The placeholder on other services that keep no empty folders.
    public static let folderPlaceholder = ".keep"
    /// Backend types with rclone's `directory_markers` option.
    static let directoryMarkerBackends: Set<String> = ["s3", "google cloud storage", "azureblob"]
    /// Backend types whose top-level entries are fixed by config (`combine`'s
    /// top-level folders are its upstreams: purging one purges that upstream).
    private static let fixedTopLevelBackends: Set<String> = ["combine"]

    /// Whether `remote` is there. `operations/stat` answers a missing path
    /// with `{"item": null}`, not an error.
    public func exists(fs: String, remote: String) async throws -> Bool {
        try await item(fs: fs, remote: remote) != nil
    }

    /// The entry at `remote`, or nil when there is none. rclone looks a
    /// file up directly and lists only the parent of a folder, so for a
    /// file in a large folder this is far cheaper than `listFiles` on its
    /// parent.
    public func item(fs: String, remote: String) async throws -> FileItem? {
        let response: OptionalStatResponse = try await call("operations/stat", params: [
            "fs": fs,
            "remote": remote,
        ])
        return response.item
    }

    /// A configured remote's backend type ("b2", "drive"), or nil when
    /// there is no such remote. Answered from rclone's config, no network.
    public func backendType(ofRemote name: String) async throws -> String? {
        let config: RemoteConfigResponse = try await call("config/get", params: ["name": name])
        return config.type
    }

    /// The remote that stores `fs`'s data: `fs`'s own remote, or the one a
    /// crypt, alias or similar wrapper points at through its `remote`
    /// setting. Nil for a local path or an on-the-fly remote.
    func baseRemote(ofFs fs: String) async throws -> (name: String, type: String)? {
        try await dataLocation(ofFs: fs).map { ($0.name, $0.type) }
    }

    /// True when `fs` is the root of a backend whose top-level entries are
    /// fixed (currently rclone's `combine` backend), directly or through
    /// wrappers (alias, crypt) with no path. Top-level folders cannot be
    /// created, renamed, moved, or deleted there; on `combine`, purging one
    /// purges that whole upstream.
    public func hasFixedTopLevel(fs: String) async throws -> Bool {
        guard let location = try await dataLocation(ofFs: fs) else { return false }
        return Self.fixedTopLevelBackends.contains(location.type) && location.atRoot
    }

    /// Where `fs`'s data lives: the remote that stores it, as `baseRemote`,
    /// and whether `fs` is that remote's own root. A path anywhere along the
    /// chain (`crypt` over `"onedrive:Vault"`, or `"name:sub"` itself) or a
    /// `root_folder_id` on the base remote means it isn't.
    func dataLocation(ofFs fs: String) async throws -> DataLocation? {
        var current = fs
        var atRoot = true
        // Wrappers nest (alias over crypt over S3); the bound stops a loop.
        for _ in 0..<5 {
            let split = Self.splitFs(current)
            guard let name = split.name else { return nil }
            if !split.root.isEmpty { atRoot = false }
            let config: RemoteConfigResponse = try await call("config/get", params: ["name": name])
            guard let type = config.type else { return nil }
            guard let wrapped = config.remote, !wrapped.isEmpty else {
                if let folder = config.rootFolderID, !folder.isEmpty { atRoot = false }
                return DataLocation(name: name, type: type, atRoot: atRoot)
            }
            current = wrapped
        }
        return nil
    }

    /// Splits `"name:path/inside"` into the remote name and the path. Nil
    /// name for a local path or an on-the-fly `:backend:` remote.
    static func splitFs(_ fs: String) -> (name: String?, root: String) {
        guard !fs.hasPrefix("/"), !fs.hasPrefix(":"), let colon = fs.firstIndex(of: ":") else {
            return (nil, fs)
        }
        let root = fs[fs.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (String(fs[..<colon]), root)
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

    /// Whether the backend can list a whole tree in one stream (`ListR`
    /// from `operations/fsinfo`) instead of folder by folder.
    func listsRecursively(fs: String) async throws -> Bool {
        let info: FsInfoResponse = try await call("operations/fsinfo", params: ["fs": fs])
        return info.features["ListR"] ?? false
    }

    /// Hash types this remote's backend supports (`Hashes` from
    /// `operations/fsinfo`), in rclone's own order, e.g. `["md5", "sha1"]`.
    /// rclone verifies a copy with the first type both sides share.
    public func hashTypes(fs: String) async throws -> [String] {
        let info: FsInfoResponse = try await call("operations/fsinfo", params: ["fs": fs])
        return info.hashes
    }
}

/// The subset of a backend's `Features` Nimbus acts on.
public struct RemoteFeatures: Sendable, Equatable, Codable {
    public let publicLink: Bool

    public init(publicLink: Bool) {
        self.publicLink = publicLink
    }
}

private struct RemoteConfigResponse: Decodable, Sendable {
    let type: String?
    /// What a wrapper (crypt, alias, chunker) wraps, e.g. `"s3:bucket/dir"`.
    let remote: String?
    /// The folder some backends (OneDrive, Drive) treat as their root.
    let rootFolderID: String?

    enum CodingKeys: String, CodingKey {
        case type, remote
        case rootFolderID = "root_folder_id"
    }
}

/// See `RcloneClient.dataLocation(ofFs:)`.
struct DataLocation: Equatable, Sendable {
    let name: String
    let type: String
    let atRoot: Bool
}

private struct OptionalStatResponse: Decodable, Sendable {
    let item: FileItem?
}

private struct PublicLinkResponse: Decodable, Sendable {
    let url: String?
}

private struct FsInfoResponse: Decodable, Sendable {
    let features: [String: Bool]
    let hashes: [String]

    enum CodingKeys: String, CodingKey {
        case features = "Features"
        case hashes = "Hashes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Features mixes booleans with the occasional non-boolean entry in
        // some rclone versions; keep the booleans, ignore the rest.
        let raw = try c.decodeIfPresent([String: LenientBool].self, forKey: .features) ?? [:]
        features = raw.compactMapValues(\.value)
        // `Hashes` is null for a backend with none (crypt reports `[]`).
        hashes = (try? c.decodeIfPresent([String].self, forKey: .hashes)) ?? []
    }
}

private struct LenientBool: Decodable, Sendable {
    let value: Bool?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Bool.self)
    }
}
