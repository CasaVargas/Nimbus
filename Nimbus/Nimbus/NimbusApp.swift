import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var daemon: RcloneDaemon
    @State private var statusService: RemoteStatusService
    @State private var mountManager = MountManager()
    @State private var fileProviderBridge = FileProviderBridge()
    @State private var settings: AppSettings
    @State private var mountConfigs = MountConfigStore()
    @State private var transferStore: TransferStore
    @State private var bookmarkStore = BookmarkStore()
    @State private var launchAtLogin = LaunchAtLoginService()

    /// Guards the parts of daemon-connect handling that must run once per
    /// process (pollers, monitors); the rest of `onDaemonConnected` is
    /// idempotent and reruns after every reconnect.
    @State private var servicesStarted = false

    init() {
        DesignSystem.Lints.runStartupChecks()
        let d = RcloneDaemon()
        let settings = AppSettings()
        _daemon = State(initialValue: d)
        _statusService = State(initialValue: RemoteStatusService(client: d.client))
        _settings = State(initialValue: settings)
        _transferStore = State(initialValue: TransferStore(
            retention: settings.transferHistoryRetention,
            notifications: TransferNotificationService(),
            notificationMode: settings.transferNotificationMode
        ))
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
                    await bootstrap()
                }
                .onChange(of: settings.transferHistoryRetention) { _, _ in
                    Task { await transferStore.applyRetention(from: settings) }
                }
                .onChange(of: settings.transferNotificationMode) { _, _ in
                    transferStore.applyNotificationMode(from: settings)
                }
                .task(id: daemon.status) {
                    // Reruns whenever the daemon (re)connects — onboarding
                    // retry, future settings-driven restarts — so mounts and
                    // File Provider domains always resync to the live port.
                    if daemon.status == .connected {
                        await onDaemonConnected()
                    }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            AppCommands()
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
                // Cleanup happens in AppDelegate.applicationShouldTerminate
                // via shutdownHandler — same path as ⌘Q and logout.
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(launchAtLogin)
        }
    }

    /// True when the process is the host of an XCTest/Swift Testing run.
    /// The test host must NOT run production startup: spawning rclone,
    /// sweeping mounts, or registering REAL File Provider domains from a
    /// test run pollutes the developer's system — and the system-launched
    /// Debug extension then holds the .appex busy, wedging the next build's
    /// test launch ("test runner timed out while preparing to run tests").
    private var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }

    /// One-shot process setup: shutdown hook, stale-mount sweep, first
    /// daemon start. Everything that depends on a connected daemon lives in
    /// `onDaemonConnected`, which the `.task(id: daemon.status)` reruns.
    private func bootstrap() async {
        guard !isRunningTests else { return }
        // Quit (⌘Q, logout, MenuBarExtra) must unmount volumes and stop the
        // daemon before the process dies — otherwise a restart finds orphan
        // `rclone serve nfs` children and stale NFS mounts.
        let transfers = transferStore
        let mounts = mountManager
        let rclone = daemon
        appDelegate.shutdownHandler = {
            transfers.stopPolling()
            await mounts.stopAll()
            rclone.stop()
        }

        await transferStore.restoreHistory(retention: settings.transferHistoryRetention)

        mountManager.rcloneBinaryPath = settings.rcloneBinaryPath
        await mountManager.cleanupStaleMounts()
        await daemon.start(binaryPath: settings.rcloneBinaryPath)

        // A login-item launch races system startup (network, external
        // volumes, Homebrew mounts). Retry a few times before giving up so
        // "starts with macOS" reliably ends in a running daemon + mounts.
        if appDelegate.wasLaunchedAtLogin {
            var attempts = 0
            while daemon.status != .connected && attempts < 3 {
                attempts += 1
                try? await Task.sleep(for: .seconds(5))
                await daemon.retry(binaryPath: settings.rcloneBinaryPath)
            }
        }
    }

    /// Runs after every daemon (re)connect. Idempotent: restoreMounts skips
    /// live mounts, addDomain is a no-op for registered domains, and
    /// syncState just rewrites the shared port/remotes snapshot.
    private func onDaemonConnected() async {
        guard !isRunningTests else { return }
        if !servicesStarted {
            servicesStarted = true
            transferStore.startPolling(client: daemon.client)
            mountManager.startHealthMonitor()
        }

        mountManager.configs = mountConfigs.configs
        await mountManager.restoreMounts(configs: mountConfigs.configs)

        // Phase 2c: refreshAll reconciles mount(8) state and FP domains against configs
        await mountManager.refreshAll()

        do {
            let remotes = try await daemon.client.listRemotes()
            await fileProviderBridge.syncAfterDaemonConnect(
                remotes: remotes,
                port: daemon.port,
                disabledDomains: settings.disabledFileProviderDomains
            )
        } catch {
            // Non-fatal — a later reconnect retriggers this task.
        }
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
