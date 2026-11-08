import Foundation
import Observation
import RcloneKit

/// The app-wide list of clouds and the cadence that keeps their status
/// fresh. Lives at app scope so the menu bar is right while the main window
/// is closed; the sidebar, Home and the companion all read it.
///
/// Refreshing = reload the list from rclone, then probe every cloud. It runs
/// on daemon connect, every `periodicInterval`, when anything posts
/// `.nimbusRemotesChanged`, and when the companion opens with stale data.
/// Concurrent callers share one run instead of stacking probes.
@Observable
@MainActor
final class CloudMonitor {
    private(set) var remotes: [Remote] = []
    /// False until the first successful list load. Selection reconciliation
    /// waits for it, so a not-yet-loaded empty list never deselects a cloud.
    private(set) var hasLoaded = false
    private(set) var lastRefresh: Date?

    static let periodicInterval: Duration = .seconds(600)
    static let staleAfter: TimeInterval = 120

    /// Returns the configured remotes, or nil when the list could not be read
    /// (daemon down): the previous list is then kept rather than emptied.
    private let loadRemotes: @MainActor () async -> [Remote]?
    private let status: RemoteStatusService
    private let now: () -> Date
    private var inFlight: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    /// Runs after each successful list load, before probing. Production
    /// uses it to record what each cloud supports (share links) for the
    /// File Provider extension.
    private let afterLoad: @MainActor ([Remote]) async -> Void

    init(loadRemotes: @escaping @MainActor () async -> [Remote]?,
         status: RemoteStatusService,
         now: @escaping () -> Date = { Date() },
         afterLoad: @escaping @MainActor ([Remote]) async -> Void = { _ in }) {
        self.loadRemotes = loadRemotes
        self.status = status
        self.now = now
        self.afterLoad = afterLoad
    }

    /// Production wiring: list via `RemotesViewModel`, refresh on change notices.
    static func live(client: RcloneClient, status: RemoteStatusService) -> CloudMonitor {
        let monitor = CloudMonitor(loadRemotes: {
            let model = RemotesViewModel(client: client)
            await model.loadRemotes()
            return model.error == nil ? model.remotes : nil
        }, status: status, afterLoad: { remotes in
            await recordCapabilities(of: remotes, client: client)
        })
        monitor.observer = NotificationCenter.default.addObserver(
            forName: .nimbusRemotesChanged, object: nil, queue: .main
        ) { [weak monitor] _ in
            Task { @MainActor in await monitor?.refresh() }
        }
        return monitor
    }

    /// `operations/fsinfo` is answered locally by rclone, so this is cheap.
    /// A cloud whose features can't be read is recorded as not sharing.
    private static func recordCapabilities(of remotes: [Remote], client: RcloneClient) async {
        guard let store = CloudCapabilities.shared else { return }
        var entries: [String: CloudCapabilities.Entry] = [:]
        for remote in remotes {
            let features = try? await client.features(fs: "\(remote.name):")
            entries[remote.name] = .init(shareLinks: features?.publicLink ?? false)
        }
        try? store.replace(with: entries)
    }

    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            guard let list = await loadRemotes() else { return }
            remotes = list
            hasLoaded = true
            lastRefresh = now()
            await afterLoad(list)
            let names = list.map(\.name)
            if !names.isEmpty { await status.probeAll(names) }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func refreshIfStale(maxAge: TimeInterval = CloudMonitor.staleAfter) async {
        if let lastRefresh, now().timeIntervalSince(lastRefresh) < maxAge { return }
        await refresh()
    }

    /// Starts the background cadence once; later calls are no-ops.
    func startPeriodicRefresh(every interval: Duration = CloudMonitor.periodicInterval) {
        guard periodic == nil else { return }
        periodic = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    /// Deletes a cloud's configuration, forgets its status, and reloads.
    func remove(_ name: String, client: RcloneClient) async {
        await RemotesViewModel(client: client).deleteRemote(name: name)
        status.clear(name)
        PinStore.shared?.removeAll(domain: name)
        await refresh()
    }
}
