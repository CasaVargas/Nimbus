import AppKit
import os

/// Lets Finder use of a drive reach the app (`NimbusWake`): a throttled
/// wake ping on every user-driven rclone call, and, when the app isn't
/// running at all, a hidden launch of the containing app.
enum AppWaker {
    private static let mainBundleID = "app.casavargas.nimbus"
    private static let pingInterval: TimeInterval = 20
    private static let launchInterval: TimeInterval = 30
    private static let state = OSAllocatedUnfairLock(initialState: (lastPing: Date.distantPast, lastLaunch: Date.distantPast))
    private static let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "wake")

    /// Tells a running app that Finder is using a drive. At most every 20 s.
    static func ping(now: Date = Date()) {
        let due = state.withLock { s -> Bool in
            guard now.timeIntervalSince(s.lastPing) >= pingInterval else { return false }
            s.lastPing = now
            return true
        }
        if due { NimbusWake.post() }
    }

    /// An rclone call failed: wake a sleeping engine now, and open Nimbus
    /// (hidden) if it isn't running and the user allows it.
    static func connectionFailed(now: Date = Date()) {
        NimbusWake.post()
        guard !isAppRunning else { return }
        let container = FileProviderRetry.appGroupContainerURL()
        guard NimbusWake.readOpensApp(in: container) else { return }
        let due = state.withLock { s -> Bool in
            guard now.timeIntervalSince(s.lastLaunch) >= launchInterval else { return false }
            s.lastLaunch = now
            return true
        }
        guard due, let appURL = containingAppURL else { return }
        NimbusWake.writeLaunchMarker(in: container, now: now)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                logger.error("Opening Nimbus failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Opened Nimbus for Finder")
            }
        }
    }

    private static var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).isEmpty
    }

    /// `…/Nimbus.app/Contents/PlugIns/FileProvider.appex` → `…/Nimbus.app`.
    private static var containingAppURL: URL? {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent()  // PlugIns
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // Nimbus.app
        return url.pathExtension == "app" ? url : nil
    }
}
