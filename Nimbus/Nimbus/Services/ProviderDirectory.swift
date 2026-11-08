import Foundation
import Observation
import RcloneKit

/// rclone backend id → human name ("drive" → "Google Drive"), loaded once per
/// daemon connection from `config/providers`. Falls back to the raw id so a
/// backend rclone added after this build still gets a label.
@Observable
@MainActor
final class ProviderDirectory {
    private(set) var descriptions: [String: String] = [:]

    func load(client: RcloneClient) async {
        guard let providers = try? await client.getProviders() else { return }
        var map: [String: String] = [:]
        for provider in providers {
            map[provider.prefix] = provider.description
            map[provider.name] = provider.description
        }
        descriptions = map
    }

    func displayName(forType type: String) -> String {
        let key = type.lowercased().trimmingCharacters(in: .whitespaces)
        if let known = descriptions[key] { return known }
        return key.isEmpty ? "Remote" : key.prefix(1).uppercased() + key.dropFirst()
    }
}
