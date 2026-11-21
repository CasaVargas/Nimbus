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
/// current port by re-reading the app group. Reads (`withReadRetry`) retry
/// anything that may be transient; writes (`withWriteRetry`) retry only when
/// rclone didn't run the call or the outcome is unknown, and each write is
/// written to be safe to re-run.
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

    /// Runs a read `body` with up to `maxAttempts` tries. Reads retry
    /// anything that may be transient, including an rclone 5xx.
    static func withReadRetry<T: Sendable>(
        rclone: RcloneClient,
        logger: Logger,
        operation: String,
        maxAttempts: Int = 5,
        wakesApp: Bool = true,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await withRetry(
            .read, rclone: rclone, logger: logger, operation: operation,
            maxAttempts: maxAttempts, wakesApp: wakesApp
        ) { _ in
            try await body()
        }
    }

    /// Runs a write `body` with up to `maxAttempts` tries. Writes retry only
    /// when rclone didn't run the call or the outcome is unknown, and each
    /// write is written to be safe to re-run (`isRetry` is `true` from the
    /// second attempt on).
    static func withWriteRetry<T: Sendable>(
        rclone: RcloneClient,
        logger: Logger,
        operation: String,
        maxAttempts: Int = 5,
        wakesApp: Bool = true,
        _ body: @Sendable (_ isRetry: Bool) async throws -> T
    ) async throws -> T {
        try await withRetry(
            .write, rclone: rclone, logger: logger, operation: operation,
            maxAttempts: maxAttempts, wakesApp: wakesApp
        ) { attempt in
            try await body(attempt > 0)
        }
    }

    /// The loop both share: `RetryPolicy.run` with the extension's side
    /// effects. Before each retry it refreshes the rclone port and
    /// credentials; the backoff is linear (1s, 2s, 3s, …).
    ///
    /// `wakesApp` (on for anything Finder asks for directly) pings the app
    /// so its idle timer restarts, and on a first retry wakes its sleeping
    /// engine or opens it (`AppWaker`). The working-set change scan passes
    /// false: it runs on its own cadence and must not keep the engine awake.
    private static func withRetry<T: Sendable>(
        _ kind: RetryPolicy.Kind,
        rclone: RcloneClient,
        logger: Logger,
        operation: String,
        maxAttempts: Int,
        wakesApp: Bool,
        _ body: @Sendable (_ attempt: Int) async throws -> T
    ) async throws -> T {
        if wakesApp { AppWaker.ping() }
        return try await RetryPolicy.run(
            kind: kind,
            maxAttempts: maxAttempts,
            operation: operation,
            logger: logger,
            beforeRetry: { attempt in
                if attempt == 1, wakesApp { AppWaker.connectionFailed() }
                refreshPort(on: rclone, logger: logger)
            },
            body
        )
    }
}
