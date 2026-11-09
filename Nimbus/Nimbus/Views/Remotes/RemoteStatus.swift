import SwiftUI

enum RemoteStatus: Equatable, Sendable {
    case unknown
    case connected
    case authNeeded
    /// The host could not be reached at all (refused, no route, DNS). Kept
    /// apart from `.error` because the fix is "be on the right network",
    /// not "change a setting", and Home words it that way.
    case unreachable(reason: String)
    case error(reason: String)

    /// Plain-language status, the same words Home and the menu bar use.
    var shortText: String {
        switch self {
        case .unknown: return "Checking…"
        case .connected: return "Ready"
        case .authNeeded: return "Needs sign-in"
        case .unreachable: return "Can't reach this server right now"
        case .error: return "Can't connect"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown: return DesignSystem.Color.semantic.textSecondary
        case .connected: return DesignSystem.Color.semantic.statusOK
        case .authNeeded: return DesignSystem.Color.semantic.statusWarning
        case .unreachable: return DesignSystem.Color.semantic.statusMuted
        case .error: return DesignSystem.Color.semantic.statusError
        }
    }

    /// The Stratosphere status this maps to. "Checking" and "can't reach"
    /// share the quiet tone: neither is something the user must fix.
    var stratosphere: StratosphereStatus {
        switch self {
        case .unknown, .unreachable: return .muted
        case .connected: return .ok
        case .authNeeded: return .warning
        case .error: return .error
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown: return "Status checking"
        case .connected: return "Ready"
        case .authNeeded: return "Sign in required"
        case .unreachable: return "Can't reach this server right now"
        case .error(let reason): return "Can't connect: \(reason)"
        }
    }
}
