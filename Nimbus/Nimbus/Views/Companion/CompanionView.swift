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
    @Environment(BackupStore.self) private var backupStore
    @Environment(BackupRunner.self) private var backupRunner
    @Environment(BackupScheduler.self) private var backupScheduler
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CompanionContent(
            summary: CloudSummaryBuilder.live(
                remotes: monitor.remotes, status: statusService, transfers: transferStore,
                providers: providers, settings: settings, daemon: daemon,
                backups: backupStore, runner: backupRunner, scheduler: backupScheduler),
            activity: ActivityLine.lines(from: transferStore.completedTransfers, limit: 3),
            openAtLogin: Binding(
                get: { launchAtLogin.isEnabled },
                set: { on in
                    if on { launchAtLogin.register() } else { Task { await launchAtLogin.unregister() } }
                }
            ),
            actions: CompanionActions(
                openCloud: { router.open(.cloud($0), openWindow: openWindow) },
                openActivity: { router.open($0, openWindow: openWindow) },
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
    @Environment(BackupStore.self) private var backupStore
    @Environment(BackupRunner.self) private var backupRunner
    @Environment(BackupScheduler.self) private var backupScheduler
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let overall = CloudSummaryBuilder.live(
            remotes: monitor.remotes, status: statusService, transfers: transferStore,
            providers: providers, settings: settings, daemon: daemon,
            backups: backupStore, runner: backupRunner, scheduler: backupScheduler
        ).overall
        Image(nsImage: MenuBarGlyph.image(badge: CompanionGlyph.badge(for: overall)))
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

/// The menu bar item's picture: the Nimbus symbol Finder shows beside its
/// locations, with a small mark in the corner while something is moving or
/// needs attention. A template image, so the menu bar tints it.
@MainActor
enum MenuBarGlyph {
    static func image(badge: CompanionGlyph.Badge, pointSize: CGFloat = 16) -> NSImage {
        let base = symbol(pointSize: pointSize)
        guard let name = badge.systemSymbol,
              let mark = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize * 0.5, weight: .heavy)) else {
            base.isTemplate = true
            return base
        }
        let disc = pointSize * 0.62
        let size = NSSize(width: base.size.width + disc * 0.35, height: base.size.height + disc * 0.2)
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: size.height - base.size.height,
                                 width: base.size.width, height: base.size.height))
            // Clear a disc out of the cloud so the mark stays readable on it.
            let discRect = NSRect(x: size.width - disc, y: 0, width: disc, height: disc)
            if let context = NSGraphicsContext.current?.cgContext {
                context.setBlendMode(.clear)
                context.fillEllipse(in: discRect.insetBy(dx: -1, dy: -1))
                context.setBlendMode(.normal)
            }
            let markSize = mark.size
            mark.draw(in: NSRect(x: discRect.midX - markSize.width / 2, y: discRect.midY - markSize.height / 2,
                                 width: markSize.width, height: markSize.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func symbol(pointSize: CGFloat) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let named = NSImage(named: CompanionGlyph.symbolName)?.withSymbolConfiguration(configuration)
        // The catalog symbol is always there; the system cloud only covers a broken build.
        return named ?? NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)!
    }
}

#if DEBUG
#Preview("Menu bar glyphs") {
    HStack(spacing: 28) {
        ForEach([CompanionGlyph.Badge.none, .uploading, .downloading, .attention], id: \.self) { badge in
            VStack(spacing: 10) {
                Image(nsImage: MenuBarGlyph.image(badge: badge, pointSize: 64))
                Image(nsImage: MenuBarGlyph.image(badge: badge))
            }
        }
    }
    .padding(30)
}
#endif
