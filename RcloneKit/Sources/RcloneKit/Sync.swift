import Foundation

/// The report lists rclone can return from `sync/sync` and `sync/copy`.
/// `match` and `combined` are deliberately absent: they list every
/// unchanged file, which is unbounded on a large backup.
public enum SyncReportKind: String, Sendable, CaseIterable {
    case missingOnDst, missingOnSrc, differ, error
}

/// One `sync/sync` or `sync/copy` call, including the per-call option
/// overlay (`_config`) and filter (`_filter`). Both apply to this call only;
/// rclone's global options are untouched (verified on 1.76).
public struct SyncRequest: Sendable, Equatable {
    public enum Operation: String, Sendable {
        case copy = "sync/copy"
        case sync = "sync/sync"
    }

    public var operation: Operation
    public var srcFs: String
    public var dstFs: String
    public var dryRun: Bool
    public var backupDir: String?
    public var maxDelete: Int?
    public var excludeRules: [String]
    public var reports: Set<SyncReportKind>

    public init(
        operation: Operation,
        srcFs: String,
        dstFs: String,
        dryRun: Bool = false,
        backupDir: String? = nil,
        maxDelete: Int? = nil,
        excludeRules: [String] = [],
        reports: Set<SyncReportKind> = []
    ) {
        self.operation = operation
        self.srcFs = srcFs
        self.dstFs = dstFs
        self.dryRun = dryRun
        self.backupDir = backupDir
        self.maxDelete = maxDelete
        self.excludeRules = excludeRules
        self.reports = reports
    }

    /// The exact RC body. Always async so the reports arrive in `job/status`.
    public var parameters: [String: any Sendable] {
        var params: [String: any Sendable] = [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
        ]
        var config: [String: any Sendable] = [:]
        if dryRun { config["DryRun"] = true }
        if let backupDir { config["BackupDir"] = backupDir }
        if let maxDelete { config["MaxDelete"] = maxDelete }
        if !config.isEmpty { params["_config"] = config }
        if !excludeRules.isEmpty { params["_filter"] = ["ExcludeRule": excludeRules] as [String: any Sendable] }
        for report in reports { params[report.rawValue] = true }
        return params
    }
}

extension RcloneClient {
    /// Starts a sync/copy job and returns rclone's job id.
    public func startSync(_ request: SyncRequest) async throws -> Int {
        let response: AsyncJobResponse = try await call(request.operation.rawValue, params: request.parameters)
        return response.jobid
    }

    public func copy(srcFs: String, dstFs: String, extraParams: [String: String] = [:]) async throws -> Int {
        guard !extraParams.isEmpty else {
            return try await startSync(SyncRequest(operation: .copy, srcFs: srcFs, dstFs: dstFs))
        }
        var params = SyncRequest(operation: .copy, srcFs: srcFs, dstFs: dstFs).parameters
        for (key, value) in extraParams { params[key] = value }
        let response: AsyncJobResponse = try await call(SyncRequest.Operation.copy.rawValue, params: params)
        return response.jobid
    }

    public func sync(srcFs: String, dstFs: String) async throws -> Int {
        try await startSync(SyncRequest(operation: .sync, srcFs: srcFs, dstFs: dstFs))
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
