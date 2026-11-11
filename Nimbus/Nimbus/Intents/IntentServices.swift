import Foundation

/// What the Shortcuts intents need from the running app. `NimbusApp.init`
/// sets `current`; intents run in the app process, so they see the same
/// daemon, stores and bridge as the windows. See
/// `docs/superpowers/specs/2026-11-11-shortcuts-design.md`.
@MainActor
final class IntentServices {
    static var current: IntentServices?

    let daemon: RcloneDaemon
    let backupStore: BackupStore
    let backupRunner: BackupRunner
    let fileProviderBridge: FileProviderBridge
    let cloudMonitor: CloudMonitor

    init(daemon: RcloneDaemon, backupStore: BackupStore, backupRunner: BackupRunner,
         fileProviderBridge: FileProviderBridge, cloudMonitor: CloudMonitor) {
        self.daemon = daemon
        self.backupStore = backupStore
        self.backupRunner = backupRunner
        self.fileProviderBridge = fileProviderBridge
        self.cloudMonitor = cloudMonitor
    }

    /// How long an intent that launched Nimbus waits for startup.
    static let readyTimeout: Duration = .seconds(20)

    static func require() throws -> IntentServices {
        guard let current else { throw ShortcutError.notRunning }
        return current
    }

    /// Waits for the rclone engine to connect.
    func waitForDaemon() async throws {
        try await Self.wait(until: { self.daemon.status == .connected }, or: .engineNotReady)
    }

    /// Waits for the backups file to be read (it loads at launch).
    func waitForBackups() async throws {
        try await Self.wait(until: { self.backupStore.loadState != .notLoaded }, or: .backupsNotLoaded)
    }

    static func wait(until ready: @MainActor () -> Bool, or failure: ShortcutError,
                     timeout: Duration = readyTimeout, step: Duration = .milliseconds(250)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !ready() {
            guard clock.now < deadline else { throw failure }
            try await Task.sleep(for: step)
        }
    }
}
