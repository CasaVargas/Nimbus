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
    @State private var diagnosticsService: DiagnosticsService
    @State private var transferNotifier: TransferNotificationService
    @State private var generalSettingsModel = GeneralSettingsModel()
    @State private var providerDirectory = ProviderDirectory()
    @State private var cloudMonitor: CloudMonitor
    @State private var router = AppRouter()
    @State private var backupStore: BackupStore
    @State private var backupRunner: BackupRunner
    @State private var backupScheduler: BackupScheduler

    /// Guards the parts of daemon-connect handling that must run once per
    /// process (pollers, monitors); the rest of `onDaemonConnected` is
    /// idempotent and reruns after every reconnect.
    @State private var servicesStarted = false

    init() {
        DesignSystem.Lints.runStartupChecks()
        let d = RcloneDaemon()
        let settings = AppSettings()
        let transferNotifier = TransferNotificationService()
        _daemon = State(initialValue: d)
        let status = RemoteStatusService(client: d.client)
        _statusService = State(initialValue: status)
        _cloudMonitor = State(initialValue: CloudMonitor.live(client: d.client, status: status))
        _settings = State(initialValue: settings)
        _diagnosticsService = State(initialValue: DiagnosticsService())
        _transferNotifier = State(initialValue: transferNotifier)
        let transfers = TransferStore(
            retention: settings.transferHistoryRetention,
            notifications: transferNotifier,
            notificationMode: settings.transferNotificationMode
        )
        _transferStore = State(initialValue: transfers)
        let backups = BackupStore()
        _backupStore = State(initialValue: backups)
        let runner = BackupRunner(
            store: backups,
            transfers: transfers,
            client: d.client,
            isDaemonConnected: { d.status == .connected }
        )
        _backupRunner = State(initialValue: runner)
        let scheduler = BackupScheduler(
            store: backups,
            launcher: runner,
            planner: BackupSchedulePlanner(calendar: .autoupdatingCurrent),
            busy: { runner.busyJobIDs }
        )
        _backupScheduler = State(initialValue: scheduler)
        // A lost scheduled run is left unrecorded; re-plan so it is caught up.
        runner.onRunLost = { [weak scheduler] in scheduler?.replan() }
        // The runner first, so the scheduler's busy set is current when it re-plans.
        backups.onJobsChanged = { [weak runner, weak scheduler] in
            runner?.jobsDidChange()
            scheduler?.replan()
        }
    }

    var body: some Scene {
        WindowGroup(id: AppRouter.mainWindowID) {
            SceneAppearanceRoot(settings: settings) {
                ContentView()
                    .environment(cloudMonitor)
                    .environment(router)
                    .environment(daemon)
                    .environment(mountManager)
                    .environment(fileProviderBridge)
                    .environment(mountConfigs)
                    .environment(transferStore)
                    .environment(backupStore)
                    .environment(backupRunner)
                    .environment(backupScheduler)
                    .environment(bookmarkStore)
                    .environment(launchAtLogin)
                    .environment(statusService)
                    .environment(providerDirectory)
                    .environment(\.diagnosticsService, diagnosticsService)
                    .environment(\.transferNotifier, transferNotifier)
            }
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
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
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
        StratosphereGalleryScene()
        #endif

        MenuBarExtra {
            SceneAppearanceRoot(settings: settings) {
                CompanionView()
                    .environment(daemon)
                    .environment(statusService)
                    .environment(transferStore)
                    .environment(providerDirectory)
                    .environment(launchAtLogin)
                    .environment(cloudMonitor)
                    .environment(backupStore)
                    .environment(backupRunner)
                    .environment(backupScheduler)
                    .environment(router)
            }
        } label: {
            CompanionMenuBarLabel()
                .environment(settings)
                .environment(daemon)
                .environment(statusService)
                .environment(transferStore)
                .environment(providerDirectory)
                .environment(cloudMonitor)
                .environment(backupStore)
                .environment(backupRunner)
                .environment(backupScheduler)
                .environment(router)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SceneAppearanceRoot(settings: settings) {
                SettingsView(generalModel: generalSettingsModel)
                    .environment(daemon)
                    .environment(launchAtLogin)
                    .environment(\.diagnosticsService, diagnosticsService)
                    .environment(\.transferNotifier, transferNotifier)
            }
        }
    }

    /// Debug builds honor `-debugWindowWidth` / `-debugWindowHeight` so a
    /// screenshot run can open a larger first window on a non-Retina display.
    private static var defaultWindowSize: CGSize {
        #if DEBUG
        let d = UserDefaults.standard
        let w = d.double(forKey: "debugWindowWidth"), h = d.double(forKey: "debugWindowHeight")
        if w >= 800, h >= 600 { return CGSize(width: w, height: h) }
        #endif
        return CGSize(width: 1000, height: 700)
    }

    /// True when the process only hosts a unit-test run or an Xcode preview.
    /// Such a host must NOT run production startup: spawning rclone, ending
    /// other rclone daemons, sweeping mounts, or registering REAL File
    /// Provider domains pollutes the developer's system and breaks the
    /// installed app running beside it. The system-launched Debug extension
    /// also holds the .appex busy, wedging the next build's test launch
    /// ("test runner timed out while preparing to run tests").
    private var isHostedLaunch: Bool {
        !LaunchContext.current.managesSystemProcesses
    }

    /// One-shot process setup: shutdown hook, stale-mount sweep, first
    /// daemon start. Everything that depends on a connected daemon lives in
    /// `onDaemonConnected`, which the `.task(id: daemon.status)` reruns.
    private func bootstrap() async {
        guard !isHostedLaunch else { return }
        // Quit (⌘Q, logout, MenuBarExtra) must unmount volumes and stop the
        // daemon before the process dies — otherwise a restart finds orphan
        // `rclone serve nfs` children and stale NFS mounts.
        let transfers = transferStore
        let mounts = mountManager
        let rclone = daemon
        let runner = backupRunner
        appDelegate.shouldConfirmQuit = { runner.isRunningAnything }
        let backups = backupStore
        appDelegate.interruptedBackupRunsAgain = {
            QuitDecision.runsAgain(interrupting: runner.busyJobIDs.compactMap { backups.job(id: $0) })
        }
        let router = router
        appDelegate.onBackupNotificationClick = { id in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            router.pending = .backups(id)
            if router.isMainWindowOpen,
               let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                router.needsWindow = true
            }
        }
        appDelegate.shutdownHandler = {
            transfers.stopPolling()
            await mounts.stopAll()
            rclone.stop()
        }

        await transferStore.restoreHistory(retention: settings.transferHistoryRetention)
        await backupStore.load()

        mountManager.rcloneBinaryPath = settings.rcloneBinaryPath
        await mountManager.cleanupStaleMounts()
        await daemon.start(
            binaryPath: settings.rcloneBinaryPath,
            bandwidthLimit: settings.bandwidthLimit,
            concurrentTransfers: settings.concurrentTransfers
        )

        // A login-item launch races system startup (network, external
        // volumes, Homebrew mounts). Retry a few times before giving up so
        // "starts with macOS" reliably ends in a running daemon + mounts.
        if appDelegate.wasLaunchedAtLogin {
            var attempts = 0
            while daemon.status != .connected && attempts < 3 {
                attempts += 1
                try? await Task.sleep(for: .seconds(5))
                await daemon.retry(
                    binaryPath: settings.rcloneBinaryPath,
                    bandwidthLimit: settings.bandwidthLimit,
                    concurrentTransfers: settings.concurrentTransfers
                )
            }
        }
    }

    /// Runs after every daemon (re)connect. Idempotent: restoreMounts skips
    /// live mounts, addDomain is a no-op for registered domains, and
    /// syncState just rewrites the shared port/remotes snapshot.
    private func onDaemonConnected() async {
        guard !isHostedLaunch else { return }
        // Every connect is a new rclone process: jobs from a previous one are
        // gone (and job ids restart), so end their transfers and let the
        // backup queue move on.
        await transferStore.abandonActiveTransfers()
        if !servicesStarted {
            servicesStarted = true
            ShareLinkNotifier.shared.start()
            transferStore.startPolling(client: daemon.client)
            mountManager.startHealthMonitor()
            cloudMonitor.startPeriodicRefresh()
            backupScheduler.start()
        } else {
            // Runs missed while the daemon was down catch up after the settle delay.
            backupScheduler.replan(catchingUp: true)
        }
        // Every (re)connect reloads the cloud list and probes each cloud, so
        // Home, the sidebar and the menu bar start from fresh status.
        Task { await cloudMonitor.refresh() }

        mountManager.configs = mountConfigs.configs
        Task { await providerDirectory.load(client: daemon.client) }
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

struct SceneAppearanceRoot<Content: View>: View {
    private let settings: AppSettings
    private let content: Content

    init(settings: AppSettings, @ViewBuilder content: () -> Content) {
        self.settings = settings
        self.content = content()
    }

    var body: some View {
        content
            .environment(settings)
            .preferredColorScheme(settings.colorScheme)
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
