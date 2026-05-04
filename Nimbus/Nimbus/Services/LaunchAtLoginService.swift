import Foundation
import Observation
import os
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "launchatlogin")

    init() {
        refresh()
    }

    func refresh() {
        // Clear any stale error so the caption disappears once the underlying
        // condition is fixed (e.g., user moved the app to /Applications).
        lastError = nil
        isEnabled = SMAppService.mainApp.status == .enabled
        logger.info("Launch-at-login status refreshed: \(self.isEnabled)")
    }

    func register() {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
            lastError = nil
            logger.info("Registered as login item")
        } catch {
            lastError = Self.message(for: error)
            isEnabled = SMAppService.mainApp.status == .enabled
            logger.error("Register failed: \(error.localizedDescription)")
        }
    }

    func unregister() async {
        do {
            try await SMAppService.mainApp.unregister()
            isEnabled = false
            lastError = nil
            logger.info("Unregistered as login item")
        } catch {
            lastError = Self.message(for: error)
            isEnabled = SMAppService.mainApp.status == .enabled
            logger.error("Unregister failed: \(error.localizedDescription)")
        }
    }

    /// Maps known SMAppService failures to user-facing strings.
    /// SMAppService.mainApp.register() refuses to register when the bundle
    /// isn't in /Applications or ~/Applications, so we check that condition
    /// directly and surface a precise hint.
    private static func message(for error: Error) -> String {
        if !isInApplicationsFolder() {
            return "Move Nimbus to your Applications folder, then try again."
        }
        return error.localizedDescription
    }

    private static func isInApplicationsFolder() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix("\(NSHomeDirectory())/Applications/")
    }
}
