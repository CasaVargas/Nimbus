import AppKit
import Observation
import SwiftUI

/// A one-shot request for the main window, posted by surfaces outside it (the
/// menu bar companion, Home's toolbar) and consumed by the view that can act
/// on it. Using state instead of a notification means a request survives
/// the main window being created in response to it.
@Observable
@MainActor
final class AppRouter {
    enum Route: Equatable {
        case home
        case cloud(String)
        case transfers(String)
        case signIn(String)
        case addCloud
        /// The Backups screen, scrolled to a job when there is one.
        case backups(UUID?)
    }

    var pending: Route?
    /// Maintained by the main window's root view, so the companion knows
    /// whether to bring a window forward or ask SwiftUI for a new one.
    var isMainWindowOpen = false

    /// Returns and clears `pending` when `accepts` says this consumer owns it.
    func take(where accepts: (Route) -> Bool) -> Route? {
        guard let route = pending, accepts(route) else { return nil }
        pending = nil
        return route
    }

    /// Shows the main window (re-creating it if it was closed), then routes.
    func open(_ route: Route?, openWindow: OpenWindowAction) {
        if let route { pending = route }
        NSApp.setActivationPolicy(.regular)
        if isMainWindowOpen,
           let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.mainWindowID)
        }
        NSApp.activate()
    }

    static let mainWindowID = "main"
}
