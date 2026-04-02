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

    public var id: String { path }

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

public struct ProviderOption: Codable, Sendable, Identifiable {
    public let name: String
    public let help: String
    public let defaultValue: String
    public let value: String
    public let type: String
    public let required: Bool
    public let isPassword: Bool
    public let advanced: Bool
    public let examples: [ProviderExample]?

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

public struct ProviderExample: Codable, Sendable {
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
    public let path: String
    public let status: Int
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
