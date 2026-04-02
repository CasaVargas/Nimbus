import FileProvider
import Foundation
import os

@MainActor @Observable
final class FileProviderBridge {
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "fileprovider")
    private static let appGroupID = "group.app.casavargas.nimbus"
    private(set) var activeDomains: Set<String> = []

    func refreshDomains() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            activeDomains = Set(domains.map { $0.identifier.rawValue })
        } catch {
            logger.debug("Failed to refresh domains: \(error.localizedDescription)")
        }
    }

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
        // Write to UserDefaults
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        defaults?.set(port, forKey: "rclonePort")
        defaults?.set(remotes, forKey: "remotes")
        defaults?.set(Date().timeIntervalSince1970, forKey: "updatedAt")

        // Write JSON to every location the extension might find it:
        // 1. Group container (works when app group is properly provisioned)
        // 2. Extension's sandbox container (main app is unsandboxed so can write here)
        let state: [String: Any] = [
            "rclonePort": port,
            "remotes": remotes,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }

        let paths = Self.sharedStatePaths()
        for path in paths {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }

        logger.info("Synced state: port=\(port), remotes=\(remotes)")
    }

    /// All possible locations for the shared state file. The main app writes
    /// to all of them; the extension reads from whichever one it can access.
    private static func sharedStatePaths() -> [String] {
        let home = NSHomeDirectory()  // real home for unsandboxed main app
        let extensionContainer = "\(home)/Library/Containers/app.casavargas.nimbus.FileProvider/Data"
        return [
            // Group container (ideal, requires provisioned app group)
            "\(home)/Library/Group Containers/\(appGroupID)/shared-state.json",
            // Extension's sandbox container (always writable by unsandboxed main app)
            "\(extensionContainer)/Library/Application Support/shared-state.json",
        ]
    }

    /// Tells all File Provider domains to re-enumerate their contents.
    /// Call this after rclone becomes healthy so the extension retries.
    func signalAllDomains() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            for domain in domains {
                if let manager = NSFileProviderManager(for: domain) {
                    try? await manager.signalEnumerator(for: .rootContainer)
                    try? await manager.signalEnumerator(for: .workingSet)
                    logger.info("Signaled domain: \(domain.identifier.rawValue)")
                }
            }
        } catch {
            logger.debug("Failed to signal domains: \(error.localizedDescription)")
        }
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
