import FileProvider
import RcloneKit
import os

/// Shared port-discovery and retry/backoff logic for every entry point that
/// talks to the rclone daemon from the File Provider extension.
///
/// Every call site (item lookup, enumeration, content transfer, and
/// mutation) can race the daemon's startup, or the main app relaunching
/// rclone on a different port between extension process launches — the
/// extension is stateless across launches (rule 4) and only learns the
/// current port by re-reading the app group. Centralizing the retry loop
/// here means every method gets the same behavior instead of duplicating
/// ad hoc backoff loops (this was previously only implemented inside
/// `FileProviderEnumerator.enumerateItems`).
enum FileProviderRetry {
    private static let appGroupID = "group.app.casavargas.nimbus"

    /// Re-reads the rclone port from the app group and pushes it into
    /// `rclone` if it changed since the client was created/last refreshed.
    static func refreshPort(on rclone: RcloneClient, logger: Logger) {
        let port = readPort()
        let currentPort = rclone.port
        if port != currentPort {
            logger.info("Port changed: \(currentPort) → \(port)")
            rclone.updatePort(port)
        }
    }

    /// Three-way fallback for discovering the rclone daemon's RC port,
    /// mirroring how the main app publishes it: app-group `UserDefaults`
    /// first (fast path, works once both processes have entitlement access
    /// settled), then a `shared-state.json` file in the app-group container,
    /// then the same file under the extension's own Application Support
    /// (the unsandboxed main app can write there too). Falls back to
    /// rclone's documented default port if all three are unavailable.
    static func readPort() -> Int {
        let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "extension")

        if let defaults = UserDefaults(suiteName: appGroupID),
           case let port = defaults.integer(forKey: "rclonePort"), port > 0 {
            logger.debug("Read port \(port) from UserDefaults")
            return port
        }

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            if let port = readPortFromJSON(containerURL.appendingPathComponent("shared-state.json")) {
                logger.debug("Read port \(port) from group container")
                return port
            }
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let appSupport {
            if let port = readPortFromJSON(appSupport.appendingPathComponent("shared-state.json")) {
                logger.debug("Read port \(port) from Application Support")
                return port
            }
        }

        logger.warning("App group port not found, using default 5572")
        return 5572
    }

    /// Returns the app group container URL used for persisted extension
    /// state (e.g. enumerator sync-anchor snapshots). `nil` if the app group
    /// container isn't reachable, in which case callers should degrade
    /// gracefully rather than crash.
    static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func readPortFromJSON(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["rclonePort"] as? Int, port > 0 else { return nil }
        return port
    }

    /// Runs `body` with up to `maxAttempts` tries, refreshing the rclone
    /// port and backing off linearly (1s, 2s, 3s, …) between attempts. Every
    /// rclone-backed entry point in the extension routes through this so a
    /// not-yet-ready daemon, or a port change picked up mid-retry, doesn't
    /// surface as a hard failure to Finder on the first launch race.
    static func withRetry<T: Sendable>(
        rclone: RcloneClient,
        logger: Logger,
        operation: String,
        maxAttempts: Int = 5,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            if attempt > 0 {
                refreshPort(on: rclone, logger: logger)
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
            do {
                return try await body()
            } catch {
                lastError = error
                logger.warning("\(operation) attempt \(attempt + 1)/\(maxAttempts) failed on port \(rclone.port): \(String(describing: error))")
            }
        }
        logger.error("\(operation) exhausted \(maxAttempts) attempts")
        throw lastError ?? NSFileProviderError(.serverUnreachable)
    }
}
