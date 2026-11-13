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
    private static let appGroupID = AppGroup.identifier

    /// Re-reads the daemon's port and RC credentials from the shared state
    /// and pushes whatever changed into `rclone`. The app picks a new port
    /// and a new credential pair on every daemon launch.
    static func refreshPort(on rclone: RcloneClient, logger: Logger) {
        let connection = readConnection()
        let currentPort = rclone.port
        if connection.port != currentPort {
            logger.info("Port changed: \(currentPort) → \(connection.port)")
            rclone.updatePort(connection.port)
        }
        if connection.credentials != rclone.credentials {
            logger.info("RC credentials changed")
            rclone.updateCredentials(connection.credentials)
        }
    }

    /// Discovers how to reach the app's rclone daemon, mirroring how the main
    /// app publishes it: the `shared-state.json` the app writes into the
    /// app-group container, then the copy in the extension's own Application
    /// Support (the unsandboxed main app can write there too). Only those
    /// files carry the RC credentials. Then app-group `UserDefaults` (port
    /// only, written by older builds), then rclone's default port.
    static func readConnection() -> (port: Int, credentials: RCCredentials?) {
        let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "extension")

        var files: [(URL, String)] = []
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            files.append((containerURL.appendingPathComponent("shared-state.json"), "group container"))
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            files.append((appSupport.appendingPathComponent("shared-state.json"), "Application Support"))
        }
        for (url, label) in files {
            guard let data = try? Data(contentsOf: url),
                  let state = DaemonConnectionState(data: data) else { continue }
            logger.debug("Read port \(state.port) from \(label)")
            var credentials: RCCredentials?
            if let user = state.rcUser, let password = state.rcPassword {
                credentials = RCCredentials(user: user, password: password)
            }
            return (state.port, credentials)
        }

        if let defaults = UserDefaults(suiteName: appGroupID),
           case let port = defaults.integer(forKey: DaemonConnectionState.portKey), port > 0 {
            logger.debug("Read port \(port) from UserDefaults")
            return (port, nil)
        }

        logger.warning("App group port not found, using default 5572")
        return (5572, nil)
    }

    /// Returns the app group container URL used for persisted extension
    /// state (e.g. enumerator sync-anchor snapshots). `nil` if the app group
    /// container isn't reachable, in which case callers should degrade
    /// gracefully rather than crash.
    static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
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
