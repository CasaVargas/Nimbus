import FileProvider
import Foundation
import os

/// Abstracts the File Provider bridge so callers (e.g. `QuickLookHost`) can be
/// tested without standing up real `NSFileProviderManager` infrastructure.
///
/// `urlForItem` is async because the only macOS-available way to resolve the
/// Finder-visible URL for a File Provider domain
/// (`NSFileProviderManager.getUserVisibleURL(for:)`) is itself async. The
/// per-domain `documentStorageURL` property is iOS-only.
@MainActor
protocol FileProviderBridgeProtocol: AnyObject {
    func isRegistered(remote: String) -> Bool
    func urlForItem(remote: String, path: String) async -> URL?
    func isItemMaterialized(remote: String, path: String) async -> Bool
    func wasRecentlyEvicted(remote: String, path: String) async -> Bool
}

@MainActor @Observable
final class FileProviderBridge {
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "fileprovider")
    private static let appGroupID = "group.app.casavargas.nimbus"
    private(set) var activeDomains: Set<String> = []

    /// Per-domain cache of basenames currently materialized to the FP cache.
    /// The materialized enumerator is domain-wide, not folder-scoped, so we
    /// key by remote only. TTL = 5s to avoid hammering FP on every scroll.
    private let materializedCache = TimedCache<String, Set<String>>(ttl: .seconds(5))

    func refreshDomains() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            activeDomains = Set(domains.map { $0.identifier.rawValue })
        } catch {
            logger.debug("Failed to refresh domains: \(error.localizedDescription)")
        }
    }

    func addDomain(identifier: String, displayName: String) async throws {
        let existing = try await NSFileProviderManager.domains()
        if existing.contains(where: { $0.identifier.rawValue == identifier }) {
            // Already registered — leave it alone. Removing and re-adding
            // (the old behavior) tears down the domain's local replica:
            // every materialized file is evicted and pending local edits
            // are discarded, on every app launch.
            return
        }

        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: identifier),
            displayName: displayName
        )
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

    /// Full domain sync for a freshly connected daemon: push port + remotes
    /// to the extension, register a domain per remote (except user-disabled
    /// ones), drop domains for remotes that no longer exist, refresh the
    /// active set, and signal enumerators. Idempotent — safe to call again
    /// after every daemon (re)start, which is exactly when the extension's
    /// port knowledge goes stale.
    func syncAfterDaemonConnect(remotes: [String], port: Int, disabledDomains: Set<String>) async {
        syncState(remotes: remotes, port: port)
        for remote in remotes where !disabledDomains.contains(remote) {
            try? await addDomain(identifier: remote, displayName: remote)
        }
        _ = await cleanupStaleDomains(activeRemotes: remotes)
        await refreshDomains()
        await signalAllDomains()
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

// MARK: - FileProviderBridgeProtocol

extension FileProviderBridge: FileProviderBridgeProtocol {
    /// Whether the user has registered the given remote with the File Provider
    /// extension — i.e. whether it shows up as a Finder mount.
    func isRegistered(remote: String) -> Bool {
        activeDomains.contains(remote)
    }

    /// Best-effort resolution of the Finder-visible URL for a (remote, path)
    /// pair. Returns nil if the domain cannot be resolved by
    /// `NSFileProviderManager` (e.g. the extension hasn't finished registering
    /// yet). Callers should fall back to a temp-download path.
    func urlForItem(remote: String, path: String) async -> URL? {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: remote),
            displayName: remote
        )
        guard let manager = NSFileProviderManager(for: domain) else { return nil }
        guard let rootURL = try? await manager.getUserVisibleURL(for: .rootContainer) else {
            return nil
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return rootURL.appendingPathComponent(trimmed)
    }

    /// Query whether the (remote, path) item has been materialized to the
    /// local File Provider cache. Walks the domain's
    /// `enumeratorForMaterializedItems` and caches the resulting set of
    /// basenames per-domain for 5 seconds.
    ///
    /// Limitation: `NSFileProviderItem` exposes `filename` + opaque
    /// `parentItemIdentifier` but no full path. Walking the parent chain
    /// for every item would be expensive and the identifiers are
    /// extension-internal. We match on basename, which means two distinct
    /// paths within the same remote that share a filename will both
    /// report `true` if either is materialized. Accepted approximation
    /// for a non-critical badge surface.
    func isItemMaterialized(remote: String, path: String) async -> Bool {
        if let cached = materializedCache.value(for: remote) {
            return cached.contains((path as NSString).lastPathComponent)
        }
        let names = await loadMaterializedBasenames(remote: remote)
        materializedCache.store(names, for: remote)
        return names.contains((path as NSString).lastPathComponent)
    }

    /// File Provider does not expose an evicted-items enumerator on
    /// macOS 26 / iOS 18 (only materialized + pending sets exist). True
    /// eviction tracking would require a previous-snapshot diff that's
    /// out of scope here. Returns `false` so paths render as `.cloud`
    /// instead of `.evicted` — the badge surface degrades gracefully.
    // TODO Phase 3: track materialized-set transitions to surface evicted state.
    func wasRecentlyEvicted(remote _: String, path _: String) async -> Bool {
        false
    }

    private func loadMaterializedBasenames(remote: String) async -> Set<String> {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: remote),
            displayName: remote
        )
        guard let manager = NSFileProviderManager(for: domain) else {
            return []
        }
        let enumerator = manager.enumeratorForMaterializedItems()
        var collected: Set<String> = []
        // Defensive absolute cap: walk at most 32 pages. This bounds
        // worst-case walk time against a misbehaving extension that
        // returns a non-nil next page indefinitely. It is NOT a
        // temporal truncation — the 5s cache TTL does not cause a
        // deeper walk on the next refresh; every refresh re-truncates
        // at the same boundary. Items beyond page 32 will therefore be
        // missing from the cache for the remote until the materialized
        // set actually shrinks below the cap. A warning is logged when
        // the cap is hit so stale-badge reports on large domains are
        // diagnosable.
        let maxPages = 32
        var nextPage: NSFileProviderPage? = NSFileProviderPage(rawValue: Data())
        var pagesWalked = 0
        while let current = nextPage, pagesWalked < maxPages {
            let (names, next) = await enumeratePage(enumerator: enumerator, startingAt: current)
            collected.formUnion(names)
            nextPage = next
            pagesWalked += 1
        }
        if nextPage != nil {
            logger.warning("loadMaterializedBasenames: hit \(maxPages)-page cap for remote '\(remote)'; materialized set may be incomplete")
        }
        return collected
    }

    private func enumeratePage(
        enumerator: any NSFileProviderEnumerator,
        startingAt page: NSFileProviderPage
    ) async -> (Set<String>, NSFileProviderPage?) {
        await withCheckedContinuation { continuation in
            let observer = MaterializationObserver { names, next in
                continuation.resume(returning: (names, next))
            }
            enumerator.enumerateItems(for: observer, startingAt: page)
        }
    }
}

/// Collects basenames from one page of an `NSFileProviderEnumerator`.
/// The framework invokes `didEnumerate` zero or more times then exactly
/// one of `finishEnumerating(upTo:)` or `finishEnumeratingWithError`.
/// We resume the continuation on whichever terminal callback fires —
/// errors are treated as an empty result with no next page so the
/// cache doesn't hold a broken state forever and the page loop stops.
private final class MaterializationObserver: NSObject, NSFileProviderEnumerationObserver, @unchecked Sendable {
    private let completion: (Set<String>, NSFileProviderPage?) -> Void
    private var collected: Set<String> = []
    private var finished = false

    init(completion: @escaping (Set<String>, NSFileProviderPage?) -> Void) {
        self.completion = completion
    }

    func didEnumerate(_ updatedItems: [any NSFileProviderItem]) {
        for item in updatedItems {
            collected.insert(item.filename)
        }
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        guard !finished else { return }
        finished = true
        completion(collected, nextPage)
    }

    func finishEnumeratingWithError(_: any Error) {
        guard !finished else { return }
        finished = true
        completion(collected, nil)
    }
}
