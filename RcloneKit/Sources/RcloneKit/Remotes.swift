import Foundation

extension RcloneClient {
    public func listRemotes() async throws -> [String] {
        let response: RemoteListResponse = try await call("config/listremotes")
        return response.remotes
    }

    public func configDump() async throws -> [String: [String: String]] {
        try await call("config/dump")
    }

    public func getProviders() async throws -> [Provider] {
        let response: ProvidersResponse = try await call("config/providers")
        return response.providers
    }

    public func createRemote(
        name: String,
        type: String,
        parameters: [String: String] = [:]
    ) async throws {
        var params: [String: any Sendable] = [
            "name": name,
            "type": type,
        ]
        params["parameters"] = parameters
        try await call("config/create", params: params)
    }

    public func updateRemote(
        name: String,
        parameters: [String: String]
    ) async throws {
        try await call("config/update", params: [
            "name": name,
            "parameters": parameters,
        ])
    }

    public func deleteRemote(name: String) async throws {
        try await call("config/delete", params: ["name": name])
    }
}
