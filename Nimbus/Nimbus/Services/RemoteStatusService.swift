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
    /// Capacity per remote, filled from the same `operations/about` call the
    /// probe makes. Absent when the backend reports nothing usable.
    private(set) var quotas: [String: StorageQuota] = [:]

    /// When each remote last answered a probe. Persisted so Home can say
    /// "Last connected Friday" for a NAS that is only reachable at home.
    private(set) var lastConnected: [String: Date]

    private let client: RemoteProbeClient
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private static let lastConnectedKey = "remoteLastConnected"

    init(client: RemoteProbeClient, defaults: UserDefaults = .standard,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.defaults = defaults
        self.now = now
        let stored = defaults.dictionary(forKey: Self.lastConnectedKey) as? [String: Date] ?? [:]
        lastConnected = stored
    }

    private func recordConnected(_ name: String) {
        lastConnected[name] = now()
        defaults.set(lastConnected, forKey: Self.lastConnectedKey)
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
            let about = try await client.about(fs: "\(name):")
            statuses[name] = .connected
            quotas[name] = StorageQuota(about: about)
            recordConnected(name)
        } catch {
            statuses[name] = Self.classify(error)
            quotas.removeValue(forKey: name)
        }
    }

    /// Refresh only the capacity numbers, leaving the status dot alone. A
    /// failure here is not a connectivity verdict; it just clears the gauge.
    func refreshQuota(_ name: String) async {
        guard !name.isEmpty else { return }
        do {
            let about = try await client.about(fs: "\(name):")
            quotas[name] = StorageQuota(about: about)
        } catch {
            quotas.removeValue(forKey: name)
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
        quotas.removeValue(forKey: name)
        if lastConnected.removeValue(forKey: name) != nil {
            defaults.set(lastConnected, forKey: Self.lastConnectedKey)
        }
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
        // Host-level failures mean "not reachable from here right now" (a
        // NAS off the home network, a server that is down), not a broken
        // configuration. Home words these differently, so split them out.
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
            .networkConnectionLost].contains(urlError.code) {
            return .unreachable(reason: error.localizedDescription)
        }
        let unreachableSignals = [
            "connection refused", "no route to host", "network is unreachable",
            "no such host", "host is down", "i/o timeout", "connection timed out",
        ]
        if unreachableSignals.contains(where: { message.contains($0) }) {
            return .unreachable(reason: error.localizedDescription)
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
