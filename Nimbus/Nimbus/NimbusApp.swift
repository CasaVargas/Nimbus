import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var daemon: RcloneDaemon
    @State private var statusService: RemoteStatusService
    @State private var mountManager = MountManager()
    @State private var fileProviderBridge = FileProviderBridge()
    @State private var settings = AppSettings()
    @State private var mountConfigs = MountConfigStore()
    @State private var transferStore = TransferStore()
    @State private var bookmarkStore = BookmarkStore()
    @State private var launchAtLogin = LaunchAtLoginService()

    init() {
        DesignSystem.Lints.runStartupChecks()
        let d = RcloneDaemon()
        _daemon = State(initialValue: d)
        _statusService = State(initialValue: RemoteStatusService(client: d.client))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(daemon)
                .environment(mountManager)
                .environment(fileProviderBridge)
                .environment(settings)
                .environment(mountConfigs)
                .environment(transferStore)
                .environment(bookmarkStore)
                .environment(launchAtLogin)
                .environment(statusService)
                .preferredColorScheme(settings.colorScheme)
                .task {
                    await startApp()
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            #if DEBUG
            CommandMenu("Debug") {
                OpenBenchCommand()
            }
            #endif
        }

        #if DEBUG
        BenchScene()
        #endif

        MenuBarExtra("Nimbus", systemImage: "cloud") {
            Button("Show Nimbus") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") {
                Task {
                    await shutdown()
                    NSApp.terminate(nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(launchAtLogin)
        }
    }

    private func startApp() async {
        await mountManager.cleanupStaleMounts()
        await daemon.start(binaryPath: settings.rcloneBinaryPath)

        if daemon.status == .connected {
            transferStore.startPolling(client: daemon.client)
            mountManager.startHealthMonitor()

            for config in mountConfigs.configs where config.autoMount {
                if config.backend == .nfs {
                    try? await mountManager.mountConfig(config)
                }
            }

            // Sync File Provider domains
            do {
                let remotes = try await daemon.client.listRemotes()
                fileProviderBridge.syncState(remotes: remotes, port: daemon.port)
                for remote in remotes {
                    try? await fileProviderBridge.addDomain(identifier: remote, displayName: remote)
                }
                _ = await fileProviderBridge.cleanupStaleDomains(activeRemotes: remotes)
                await fileProviderBridge.refreshDomains()
                // Signal extensions to re-enumerate now that rclone is ready
                await fileProviderBridge.signalAllDomains()
            } catch {
                // Non-fatal
            }
        }
    }

    private func shutdown() async {
        transferStore.stopPolling()
        await mountManager.stopAll()
        daemon.stop()
    }
}

#if DEBUG
private struct OpenBenchCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Bench") { openWindow(id: "bench") }
            .keyboardShortcut("b", modifiers: [.option, .command])
    }
}
#endif
