import Foundation
import Observation
import RcloneKit

/// Owner of per-remote connectivity / auth state. Runs `operations/about`
/// probes on RemotesSidebarSection appear and on Reconnect. Probes are fire-once;
/// no timers, no polling. Status is cleared when a remote is deleted.
///
/// Reference: macOS Disk Utility's volume-info refresh-on-appear pattern.
@Observable
@MainActor
final class RemoteStatusService {
    private(set) var statuses: [String: RemoteStatus] = [:]

    private let client: RemoteProbeClient

    init(client: RemoteProbeClient) {
        self.client = client
    }

    /// Pre-flight marker — sets statuses[name] = .unknown synchronously
    /// before any await, so the row shows the "Checking…" pill the moment
    /// `probeAll` is called rather than waiting for the first response.
    func markUnknown(_ name: String) {
        guard !name.isEmpty else { return }
        statuses[name] = .unknown
    }

    /// Probe a single remote. Used by the Reconnect button and from
    /// `probeAll`. Replaces any prior status for `name`.
    func probe(_ name: String) async {
        guard !name.isEmpty else { return }
        statuses[name] = .unknown
        do {
            _ = try await client.about(fs: "\(name):")
            statuses[name] = .connected
        } catch {
            statuses[name] = Self.classify(error)
        }
    }

    /// Probe many remotes in parallel via a TaskGroup. Each entry is
    /// independently set; a failure on one remote does not abort the others.
    func probeAll(_ names: [String]) async {
        for name in names {
            markUnknown(name)
        }
        await withTaskGroup(of: Void.self) { group in
            for name in names where !name.isEmpty {
                group.addTask {
                    await self.probe(name)
                }
            }
        }
    }

    /// Drop the cached status for `name` (e.g., on remote deletion).
    func clear(_ name: String) {
        statuses.removeValue(forKey: name)
    }

    /// Classifies a probe failure into a RemoteStatus. Pulled out as a
    /// `static` so the tests can exercise the classifier without spinning
    /// up the service.
    static func classify(_ error: Error) -> RemoteStatus {
        if let rcloneError = error as? RcloneError, case .requestFailed(let status, _) = rcloneError {
            if status == 401 || status == 403 {
                return .authNeeded
            }
        }
        let message = error.localizedDescription.lowercased()
        let authSignals = ["oauth", "token", "unauthorized", "forbidden", "sign in", "401", "403"]
        if authSignals.contains(where: { message.contains($0) }) {
            return .authNeeded
        }
        // A request timeout is NOT a hard failure — `operations/about` can be
        // genuinely slow on large accounts, and the remote is still configured
        // and authenticated. Painting a red error dot here is a false alarm, so
        // fall back to the neutral "unknown" state instead.
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .unknown
        }
        return .error(reason: error.localizedDescription)
    }
}

/// Protocol for the single rclone RC method `RemoteStatusService` needs.
/// Lets tests inject a mock without depending on URLSession.
protocol RemoteProbeClient: Sendable {
    func about(fs: String) async throws -> AboutResponse
}

extension RcloneClient: RemoteProbeClient {}
