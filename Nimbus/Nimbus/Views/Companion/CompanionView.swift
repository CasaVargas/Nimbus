import SwiftUI

/// The menu bar window. Reads the same live services as Home through
/// `CloudSummaryBuilder.live`, so the two can never disagree, and routes
/// every action into the main window via `AppRouter`.
struct CompanionView: View {
    @Environment(CloudMonitor.self) private var monitor
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(TransferStore.self) private var transferStore
    @Environment(ProviderDirectory.self) private var providers
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(LaunchAtLoginService.self) private var launchAtLogin
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CompanionContent(
            summary: CloudSummaryBuilder.live(
                remotes: monitor.remotes, status: statusService, transfers: transferStore,
                providers: providers, settings: settings, daemon: daemon),
            activity: ActivityLine.lines(from: transferStore.completedTransfers, limit: 3),
            openAtLogin: Binding(
                get: { launchAtLogin.isEnabled },
                set: { on in
                    if on { launchAtLogin.register() } else { Task { await launchAtLogin.unregister() } }
                }
            ),
            actions: CompanionActions(
                openCloud: { router.open(.cloud($0), openWindow: openWindow) },
                signIn: { router.open(.signIn($0.name), openWindow: openWindow) },
                fix: { row in
                    if row.health == .unreachable {
                        Task { await statusService.probe(row.name) }
                    } else {
                        router.open(.cloud(row.name), openWindow: openWindow)
                    }
                },
                showTransfers: { cloud in
                    router.open(cloud.map(AppRouter.Route.transfers) ?? .home, openWindow: openWindow)
                },
                addCloud: { router.open(.addCloud, openWindow: openWindow) },
                showBackups: { router.open(.backups(nil), openWindow: openWindow) },
                openNimbus: { router.open(nil, openWindow: openWindow) },
                restartEngine: {
                    Task {
                        await daemon.retry(binaryPath: settings.rcloneBinaryPath,
                                           bandwidthLimit: settings.bandwidthLimit,
                                           concurrentTransfers: settings.concurrentTransfers)
                    }
                },
                quit: { NSApp.terminate(nil) }
            )
        )
        .task {
            launchAtLogin.refresh()
            await monitor.refreshIfStale()
        }
    }
}

/// The menu bar glyph itself: a template SF Symbol that changes with state.
struct CompanionMenuBarLabel: View {
    @Environment(CloudMonitor.self) private var monitor
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(TransferStore.self) private var transferStore
    @Environment(ProviderDirectory.self) private var providers
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let overall = CloudSummaryBuilder.live(
            remotes: monitor.remotes, status: statusService, transfers: transferStore,
            providers: providers, settings: settings, daemon: daemon
        ).overall
        Image(systemName: CompanionGlyph.symbol(for: overall))
            .accessibilityLabel(Text(verbatim: CompanionGlyph.accessibilityLabel(for: overall)))
            // A notification click posts a route even when the window was
            // closed; this label is always alive, so it can reopen the window.
            .onChange(of: router.needsWindow) {
                if router.takeWindowRequest() {
                    router.open(nil, openWindow: openWindow)
                }
            }
    }
}
