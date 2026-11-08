import Foundation

// MARK: - File Operations

public struct FileItem: Codable, Identifiable, Sendable {
    public let path: String
    public let name: String
    public let size: Int64
    public let mimeType: String
    public let modTime: Date?
    public let isDir: Bool
    public let fileID: String?

    /// The fully-qualified rclone path in the form `remote:dir/name`, set by
    /// `BrowserViewModel` after each directory listing. This is used as the
    /// SwiftUI identity so that two files with the same name at the same
    /// directory level are still distinguished. `path` is kept as the
    /// rclone-relative path that API calls require.
    public let qualifiedRemotePath: String

    /// Stable SwiftUI identity. Prefers the provider-assigned `fileID` (Google
    /// Drive supplies one per file, unique even across duplicate names) and falls
    /// back to `qualifiedRemotePath` which incorporates the remote name and full
    /// directory prefix.
    public var id: String {
        if let fileID, !fileID.isEmpty {
            return fileID
        }
        return qualifiedRemotePath
    }

    /// Memberwise initialiser used by `BrowserViewModel` to construct items with
    /// a fully-qualified remote path after receiving a listing from rclone.
    public init(
        path: String,
        name: String,
        size: Int64,
        mimeType: String,
        modTime: Date?,
        isDir: Bool,
        fileID: String?,
        qualifiedRemotePath: String
    ) {
        self.path = path
        self.name = name
        self.size = size
        self.mimeType = mimeType
        self.modTime = modTime
        self.isDir = isDir
        self.fileID = fileID
        self.qualifiedRemotePath = qualifiedRemotePath
    }

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case name = "Name"
        case size = "Size"
        case mimeType = "MimeType"
        case modTime = "ModTime"
        case isDir = "IsDir"
        case fileID = "ID"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int64.self, forKey: .size)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        isDir = try container.decode(Bool.self, forKey: .isDir)
        fileID = try container.decodeIfPresent(String.self, forKey: .fileID)

        let modTimeString = try container.decodeIfPresent(String.self, forKey: .modTime)
        if let modTimeString {
            modTime = Self.parseModTime(modTimeString)
        } else {
            modTime = nil
        }
        // qualifiedRemotePath is not present in the rclone JSON response.
        // BrowserViewModel rewrites it to `remote:dir/name` after each listing.
        // Using `path` as a placeholder keeps the value non-empty in contexts
        // that bypass the ViewModel (e.g. unit tests, FileProviderExtension).
        qualifiedRemotePath = path
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(isDir, forKey: .isDir)
        try container.encodeIfPresent(fileID, forKey: .fileID)
        if let modTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: modTime), forKey: .modTime)
        }
    }

    private static func parseModTime(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Remote Configuration

public struct Remote: Sendable {
    public let name: String
    public let type: String
    public let config: [String: String]

    public init(name: String, type: String, config: [String: String]) {
        self.name = name
        self.type = type
        self.config = config
    }
}

public struct Provider: Codable, Sendable {
    public let name: String
    public let description: String
    public let prefix: String
    public let options: [ProviderOption]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case description = "Description"
        case prefix = "Prefix"
        case options = "Options"
    }
}

public struct ProviderOption: Codable, Sendable, Identifiable, Equatable {
    public let name: String
    public let help: String
    public let defaultValue: String
    public let value: String
    public let type: String
    public let required: Bool
    public let isPassword: Bool
    public let advanced: Bool
    public let examples: [ProviderExample]?
    /// rclone marks credential-ish fields `Sensitive` separately from
    /// `IsPassword`. Both must render as SecureField.
    public let sensitive: Bool
    /// Non-zero means rclone considers the option internal; don't render it.
    public let hide: Int
    /// True when the answer branches the remaining question set (s3's
    /// `provider`, `env_auth`). Answering one of these invalidates the
    /// current page and forces a re-walk.
    public let exclusive: Bool
    /// rclone's pre-rendered default string, used as the field placeholder.
    public let defaultStr: String

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case help = "Help"
        case defaultValue = "Default"
        case value = "Value"
        case type = "Type"
        case required = "Required"
        case isPassword = "IsPassword"
        case advanced = "Advanced"
        case examples = "Examples"
        case sensitive = "Sensitive"
        case hide = "Hide"
        case exclusive = "Exclusive"
        case defaultStr = "DefaultStr"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        help = try container.decode(String.self, forKey: .help)
        type = try container.decode(String.self, forKey: .type)
        required = try container.decode(Bool.self, forKey: .required)
        isPassword = try container.decode(Bool.self, forKey: .isPassword)
        advanced = try container.decode(Bool.self, forKey: .advanced)
        examples = try container.decodeIfPresent([ProviderExample].self, forKey: .examples)
        sensitive = (try? container.decode(Bool.self, forKey: .sensitive)) ?? false
        hide = (try? container.decode(Int.self, forKey: .hide)) ?? 0
        exclusive = (try? container.decode(Bool.self, forKey: .exclusive)) ?? false
        defaultStr = (try? container.decode(String.self, forKey: .defaultStr)) ?? ""

        if let s = try? container.decode(String.self, forKey: .defaultValue) {
            defaultValue = s
        } else if let i = try? container.decode(Int.self, forKey: .defaultValue) {
            defaultValue = String(i)
        } else if let b = try? container.decode(Bool.self, forKey: .defaultValue) {
            defaultValue = String(b)
        } else {
            defaultValue = ""
        }

        if let s = try? container.decode(String.self, forKey: .value) {
            value = s
        } else if let i = try? container.decode(Int.self, forKey: .value) {
            value = String(i)
        } else if let b = try? container.decode(Bool.self, forKey: .value) {
            value = String(b)
        } else {
            value = ""
        }
    }
}

public struct ProviderExample: Codable, Sendable, Equatable {
    public let value: String
    public let help: String

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case help = "Help"
    }
}

// MARK: - Jobs

public struct Job: Codable, Sendable, Identifiable {
    public let id: Int
    public let group: String
    public let startTime: String
    public let endTime: String
    public let error: String
    public let finished: Bool
    public let success: Bool
    public let duration: Double
    /// The change report of a `sync/sync` or `sync/copy` job started with
    /// report flags. Other jobs put unrelated shapes in `output` (or none),
    /// so it decodes as nil instead of failing the whole status.
    public let output: SyncReport?

    enum CodingKeys: String, CodingKey {
        case id, group, startTime, endTime, error, finished, success, duration, output
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        error = try container.decode(String.self, forKey: .error)
        finished = try container.decode(Bool.self, forKey: .finished)
        success = try container.decode(Bool.self, forKey: .success)
        duration = try container.decode(Double.self, forKey: .duration)
        output = try? container.decodeIfPresent(SyncReport.self, forKey: .output)
    }
}

/// The lists rclone returns for a sync/copy started with report flags
/// (`missingOnDst`, `missingOnSrc`, `differ`, `error`). Paths are relative
/// to the source/destination roots. A list is nil when it wasn't requested.
public struct SyncReport: Codable, Sendable, Equatable {
    public let missingOnDst: [String]?
    public let missingOnSrc: [String]?
    public let differ: [String]?
    public let error: [String]?

    public init(missingOnDst: [String]? = nil, missingOnSrc: [String]? = nil,
                differ: [String]? = nil, error: [String]? = nil) {
        self.missingOnDst = missingOnDst
        self.missingOnSrc = missingOnSrc
        self.differ = differ
        self.error = error
    }

    /// True when no list was present at all (a job that wasn't a reporting sync).
    var isAbsent: Bool { missingOnDst == nil && missingOnSrc == nil && differ == nil && error == nil }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        missingOnDst = try container.decodeIfPresent([String].self, forKey: .missingOnDst)
        missingOnSrc = try container.decodeIfPresent([String].self, forKey: .missingOnSrc)
        differ = try container.decodeIfPresent([String].self, forKey: .differ)
        error = try container.decodeIfPresent([String].self, forKey: .error)
        if isAbsent {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "not a sync report"))
        }
    }

    enum CodingKeys: String, CodingKey { case missingOnDst, missingOnSrc, differ, error }
}

// MARK: - Statistics

public struct StatsResponse: Codable, Sendable {
    public let speed: Double
    public let bytes: Int64
    public let errors: Int
    public let fatalError: Bool?
    public let checks: Int
    public let transfers: Int
    public let deletes: Int
    /// Server-side moves, including moves into `--backup-dir`.
    public let renames: Int?
    /// Directory entries listed so far (progress for checks and dry runs).
    public let listed: Int?
    public let elapsedTime: Double
    public let totalBytes: Int64
    public let totalTransfers: Int
    public let totalChecks: Int
    public let transferring: [TransferringFile]?
    public let checking: [String]?
}

public struct TransferringFile: Codable, Sendable, Identifiable {
    public let name: String
    public let size: Int64
    public let bytes: Int64
    public let percentage: Int
    public let speed: Double
    public let speedAvg: Double
    public let eta: Int?
    public let group: String

    public var id: String { name }
}

public struct BandwidthLimitResponse: Codable, Sendable {
    public let bytesPerSecond: Int64
    public let bytesPerSecondTx: Int64
    public let bytesPerSecondRx: Int64
    public let rate: String
}

/// Typed request for rclone's `options/set` RC endpoint.
///
/// rclone exposes global command flags under the `main` object, using the
/// flag's exported Go name. `Transfers` is the live equivalent of
/// `--transfers` and applies to work started after the update.
public struct SetTransfersOptionsRequest: Encodable, Sendable {
    public let main: Main

    public init(transfers: Int) {
        main = Main(transfers: transfers)
    }

    public struct Main: Encodable, Sendable {
        public let transfers: Int

        public init(transfers: Int) {
            self.transfers = transfers
        }

        enum CodingKeys: String, CodingKey {
            case transfers = "Transfers"
        }
    }
}

public struct OptionsSetResponse: Codable, Sendable {}

// MARK: - Storage Info

public struct AboutResponse: Codable, Sendable {
    public let total: Int64?
    public let used: Int64?
    public let trashed: Int64?
    public let free: Int64?
}

// MARK: - RC API Response Wrappers

public struct ListResponse: Codable, Sendable {
    public let list: [FileItem]
}

public struct StatResponse: Codable, Sendable {
    public let item: FileItem
}

public struct RemoteListResponse: Codable, Sendable {
    public let remotes: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // rclone returns {} (no "remotes" key) when there are zero remotes configured
        remotes = (try? container.decode([String].self, forKey: .remotes)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case remotes
    }
}

public struct ProvidersResponse: Codable, Sendable {
    public let providers: [Provider]
}

public struct AsyncJobResponse: Codable, Sendable {
    public let jobid: Int
}

public struct JobListResponse: Codable, Sendable {
    public let jobids: [Int]
}

// MARK: - Errors

public struct RcloneErrorResponse: Codable, Sendable {
    public let error: String
    public let path: String?
    public let status: Int?
}

public enum RcloneError: Error, LocalizedError, Sendable {
    case serverNotRunning
    case requestFailed(status: Int, message: String)
    case invalidResponse
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            "Rclone daemon is not running"
        case .requestFailed(let status, let message):
            "Request failed (\(status)): \(message)"
        case .invalidResponse:
            "Invalid response from rclone"
        case .decodingError(let detail):
            "Failed to decode response: \(detail)"
        }
    }
}
