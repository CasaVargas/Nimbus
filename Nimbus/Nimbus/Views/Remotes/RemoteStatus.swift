import SwiftUI

enum RemoteStatus: Equatable, Sendable {
    case unknown
    case connected
    case authNeeded
    case error(reason: String)

    var pillText: String {
        switch self {
        case .unknown: return "○ Checking…"
        case .connected: return "● Connected"
        case .authNeeded: return "⚠ Sign In"
        case .error: return "! Error"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown: return DesignSystem.Color.semantic.textSecondary
        case .connected: return DesignSystem.Color.semantic.statusOK
        case .authNeeded: return DesignSystem.Color.semantic.statusWarning
        case .error: return DesignSystem.Color.semantic.statusError
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown: return "Status checking"
        case .connected: return "Connected"
        case .authNeeded: return "Sign in required"
        case .error(let reason): return "Error: \(reason)"
        }
    }
}
