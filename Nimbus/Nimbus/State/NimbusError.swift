import Foundation

/// Typed error pattern shared across Nimbus view models. Generalizes Phase 1's
/// `BrowserError`. The three kinds map to distinct UI affordances:
/// - `.authFailed` → "Sign In Required" + Reconnect action
/// - `.network` → "Can't Reach Cloud" + Retry action
/// - `.other` → generic banner + Retry action
///
/// Classification is a substring heuristic over `localizedDescription`.
/// Phase 2a heuristic; richer mapping to rclone error codes can come in Phase 3.
struct NimbusError: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case authFailed
        case network
        case other
    }

    let kind: Kind
    let message: String

    static func classify(_ error: Error) -> NimbusError {
        let message = error.localizedDescription
        let lower = message.lowercased()

        let authSignals = ["auth", "unauthorized", "token", "sign in", "401", "403", "oauth"]
        if authSignals.contains(where: { lower.contains($0) }) {
            return NimbusError(kind: .authFailed, message: message)
        }

        let networkSignals = ["network", "connection", "offline", "reach", "unreachable"]
        if networkSignals.contains(where: { lower.contains($0) }) {
            return NimbusError(kind: .network, message: message)
        }

        return NimbusError(kind: .other, message: message)
    }
}
