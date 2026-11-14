import AppKit

/// Whether Nimbus shows a Dock icon while a window is up. Every place that
/// brings a window forward asks here instead of forcing `.regular`, so the
/// "Show in Dock" setting holds. Hidden launches (login, backups agent,
/// Finder) still start as `.accessory` regardless.
@MainActor
enum DockPolicy {
    nonisolated static let settingKey = "showsDockIcon"

    nonisolated static func showsDockIcon(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: settingKey) as? Bool ?? true
    }

    /// The policy for a session with a visible window.
    static func windowPolicy(showsDockIcon: Bool) -> NSApplication.ActivationPolicy {
        showsDockIcon ? .regular : .accessory
    }

    /// Call before bringing a window forward.
    static func applyForWindow(defaults: UserDefaults = .standard) {
        let policy = windowPolicy(showsDockIcon: showsDockIcon(defaults: defaults))
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// The setting changed while running: apply it now, keeping the app
    /// frontmost (dropping to `.accessory` deactivates the app).
    static func settingChanged(to showsDockIcon: Bool) {
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(windowPolicy(showsDockIcon: showsDockIcon))
        if wasActive { NSApp.activate() }
    }
}
