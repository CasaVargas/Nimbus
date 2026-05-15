import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class RemotesViewModel {
    private(set) var remotes: [Remote] = []
    private(set) var providers: [Provider] = []
    private(set) var isLoading = false
    private(set) var error: NimbusError?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let names = client.listRemotes()
            async let dump = client.configDump()
            let (remoteNames, configs) = try await (names, dump)

            remotes = remoteNames.map { name in
                let config = configs[name] ?? [:]
                return Remote(
                    name: name,
                    type: config["type"] ?? "unknown",
                    config: config
                )
            }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    func loadProviders() async {
        do {
            providers = try await client.getProviders()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    func deleteRemote(name: String) async {
        do {
            try await client.deleteRemote(name: name)
            remotes.removeAll { $0.name == name }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    func createRemote(name: String, type: String, parameters: [String: String]) async throws {
        try await client.createRemote(name: name, type: type, parameters: parameters)
        await loadRemotes()
    }

    func updateRemote(name: String, parameters: [String: String]) async throws {
        try await client.updateRemote(name: name, parameters: parameters)
        await loadRemotes()
    }
}
