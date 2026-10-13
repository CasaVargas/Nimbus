import Foundation

extension RcloneClient {
    public func getStats(group: String? = nil) async throws -> StatsResponse {
        var params: [String: any Sendable] = [:]
        if let group {
            params["group"] = group
        }
        return try await call("core/stats", params: params)
    }

    public func setBandwidthLimit(rate: String) async throws -> BandwidthLimitResponse {
        try await call("core/bwlimit", params: ["rate": rate])
    }

    public func getBandwidthLimit() async throws -> BandwidthLimitResponse {
        try await call("core/bwlimit")
    }

    /// Sets rclone's live `--transfers` option through `options/set`.
    /// Existing jobs retain the concurrency they started with; subsequent
    /// operations use this value.
    public func setConcurrentTransfers(_ transfers: Int) async throws {
        let _: OptionsSetResponse = try await call(
            "options/set",
            parameters: SetTransfersOptionsRequest(transfers: transfers)
        )
    }
}
