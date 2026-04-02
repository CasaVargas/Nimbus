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
}
