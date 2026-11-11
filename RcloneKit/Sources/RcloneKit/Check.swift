import Foundation

/// One `operations/check` call comparing two folders. Read-only: rclone
/// lists differences and never changes either side.
public struct CheckRequest: Sendable, Equatable {
    public enum Method: String, Sendable, CaseIterable {
        /// Size, plus a hash wherever both sides share a hash type.
        case checksum
        /// Size only (`--size-only`): fast, ignores content.
        case sizeOnly
    }

    public var srcFs: String
    public var dstFs: String
    public var method: Method

    public init(srcFs: String, dstFs: String, method: Method = .checksum) {
        self.srcFs = srcFs
        self.dstFs = dstFs
        self.method = method
    }

    /// The exact RC body. Always async so it can be polled and stopped;
    /// `combined` is the one list that also carries the matching files.
    public var parameters: [String: any Sendable] {
        var params: [String: any Sendable] = [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "combined": true,
            "_async": true,
        ]
        if method == .sizeOnly {
            params["_config"] = ["SizeOnly": true] as [String: any Sendable]
        }
        return params
    }
}

/// The report `operations/check` puts in its job's `output` (rclone 1.76).
/// `success` is false whenever the folders differ; that is not a failure.
public struct CheckReport: Codable, Sendable, Equatable {
    /// `<sign> <path>` lines: `=` same, `*` differ, `+` only on src,
    /// `-` only on dst, `!` error.
    public let combined: [String]
    public let hashType: String?
    public let status: String?
    public let success: Bool?

    public init(combined: [String], hashType: String? = nil, status: String? = nil, success: Bool? = nil) {
        self.combined = combined
        self.hashType = hashType
        self.status = status
        self.success = success
    }

    /// True when content wasn't compared because the two sides share no
    /// hash type (or the compare was size only).
    public var comparedWithoutHash: Bool {
        guard let hashType else { return true }
        return hashType.isEmpty || hashType.lowercased() == "none"
    }

    enum CodingKeys: String, CodingKey { case combined, hashType, status, success }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combined = try container.decode([String].self, forKey: .combined)
        hashType = try container.decodeIfPresent(String.self, forKey: .hashType)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
    }
}

/// `job/status` for a check job. Kept apart from `Job`, whose `output`
/// decodes as a sync report.
public struct CheckJobStatus: Decodable, Sendable {
    public let id: Int
    public let group: String
    public let finished: Bool
    public let success: Bool
    public let error: String
    public let output: CheckReport?

    enum CodingKeys: String, CodingKey { case id, group, finished, success, error, output }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
        finished = try container.decode(Bool.self, forKey: .finished)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        output = try? container.decodeIfPresent(CheckReport.self, forKey: .output)
    }

    public init(id: Int, group: String, finished: Bool, success: Bool, error: String = "", output: CheckReport? = nil) {
        self.id = id
        self.group = group
        self.finished = finished
        self.success = success
        self.error = error
        self.output = output
    }
}

extension RcloneClient {
    /// Starts an `operations/check` job and returns rclone's job id.
    public func startCheck(_ request: CheckRequest) async throws -> Int {
        let response: AsyncJobResponse = try await call("operations/check", params: request.parameters)
        return response.jobid
    }

    /// `job/status` for a job started by `startCheck`.
    public func checkStatus(id: Int) async throws -> CheckJobStatus {
        try await call("job/status", params: ["jobid": id])
    }
}
