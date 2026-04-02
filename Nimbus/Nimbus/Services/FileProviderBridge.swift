import FileProvider
import Foundation
import os

@MainActor @Observable
final class FileProviderBridge {
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "fileprovider")
    private static let appGroupID = "group.app.casavargas.nimbus"

    func addDomain(identifier: String, displayName: String) async throws {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: identifier),
            displayName: displayName
        )

        let existing = try await NSFileProviderManager.domains()
        if existing.contains(where: { $0.identifier.rawValue == identifier }) {
            try await NSFileProviderManager.remove(domain)
        }

        try await NSFileProviderManager.add(domain)
        logger.info("Added File Provider domain: \(identifier)")
    }

    func removeDomain(identifier: String) async throws {
        let domains = try await NSFileProviderManager.domains()
        guard let domain = domains.first(where: { $0.identifier.rawValue == identifier }) else {
            logger.warning("Domain not found for removal: \(identifier)")
            return
        }
        try await NSFileProviderManager.remove(domain)
        logger.info("Removed File Provider domain: \(identifier)")
    }

    func listDomains() async throws -> [(identifier: String, displayName: String)] {
        let domains = try await NSFileProviderManager.domains()
        return domains.map { ($0.identifier.rawValue, $0.displayName) }
    }

    func syncState(remotes: [String], port: Int) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            logger.error("Failed to access app group UserDefaults")
            return
        }
        defaults.set(port, forKey: "rclonePort")
        defaults.set(remotes, forKey: "remotes")
        defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")
        logger.info("Synced state: port=\(port), remotes=\(remotes)")
    }

    func cleanupStaleDomains(activeRemotes: [String]) async -> [String] {
        var removed: [String] = []
        do {
            let domains = try await NSFileProviderManager.domains()
            for domain in domains {
                let id = domain.identifier.rawValue
                if !activeRemotes.contains(id) {
                    do {
                        try await NSFileProviderManager.remove(domain)
                        removed.append(id)
                        logger.info("Cleaned up stale domain: \(id)")
                    } catch {
                        logger.warning("Failed to remove stale domain \(id): \(error)")
                    }
                }
            }
        } catch {
            logger.debug("File Provider not available: \(error.localizedDescription)")
        }
        return removed
    }
}
