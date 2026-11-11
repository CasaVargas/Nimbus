import AppKit
import Observation
import os
import Sparkle

/// What `UpdaterService` needs from an updater. Sparkle in the app, a fake in tests.
@MainActor
protocol UpdateDriver: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    /// False before `start()` and while a check or install is in progress.
    var canCheckForUpdates: Bool { get }
    /// Called when either value above changes, including changes the driver
    /// makes itself (Sparkle's permission prompt).
    var onChange: (@MainActor () -> Void)? { get set }
    func start()
    func checkForUpdates()
}

/// App updates through Sparkle (#100). Checks are opt-in: nothing is requested
/// until the user turns automatic checks on or chooses Check for Updates.
@MainActor
@Observable
final class UpdaterService {
    private(set) var automaticallyChecks = false
    private(set) var canCheck = false
    private(set) var hasStarted = false

    /// False in test and preview hosts and in Debug builds: no updater exists
    /// and the controls are disabled.
    var isAvailable: Bool { driver != nil }

    @ObservationIgnored private let driver: (any UpdateDriver)?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(driver: (any UpdateDriver)?) {
        self.driver = driver
        refresh()
        driver?.onChange = { [weak self] in self?.refresh() }
    }

    /// The updater for this process, or none where one must not run.
    static func live(
        context: LaunchContext = .current,
        defaults: UserDefaults = .standard
    ) -> UpdaterService {
        UpdaterService(driver: wantsUpdater(context: context, defaults: defaults) ? SparkleUpdateDriver() : nil)
    }

    /// A hosted launch never updates. Neither does a Debug build, which must
    /// not offer to replace itself with the release, unless it is launched
    /// with `-debugEnableUpdater YES`.
    static func wantsUpdater(context: LaunchContext, defaults: UserDefaults, isDebugBuild: Bool = isDebugBuild) -> Bool {
        guard context.managesSystemProcesses else { return false }
        return !isDebugBuild || defaults.bool(forKey: "debugEnableUpdater")
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func setAutomaticallyChecks(_ isOn: Bool) {
        guard let driver else { return }
        driver.automaticallyChecksForUpdates = isOn
        refresh()
    }

    func checkForUpdates() {
        guard let driver else { return }
        start()
        driver.checkForUpdates()
    }

    /// Starts the updater once. From then on Sparkle runs its scheduled
    /// checks (if allowed) and, on the second launch, asks for permission.
    func start() {
        guard let driver, !hasStarted else { return }
        hasStarted = true
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        driver.start()
        refresh()
    }

    /// Starts now if the app is frontmost, otherwise the first time it is.
    /// A login-item or backups-agent launch is hidden, and Sparkle's windows
    /// must not appear from an app the user has not opened.
    func startWhenActive(isActive: Bool = NSApp.isActive) {
        guard driver != nil, !hasStarted else { return }
        if isActive {
            start()
            return
        }
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func refresh() {
        automaticallyChecks = driver?.automaticallyChecksForUpdates ?? false
        canCheck = driver?.canCheckForUpdates ?? false
    }
}

/// Sparkle's standard updater and its standard windows.
@MainActor
final class SparkleUpdateDriver: UpdateDriver {
    var onChange: (@MainActor () -> Void)?

    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var observations: [NSKeyValueObservation] = []
    private var isStarted = false

    init() {
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
                Task { @MainActor in self?.onChange?() }
            },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
                Task { @MainActor in self?.onChange?() }
            },
        ]
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool { isStarted && controller.updater.canCheckForUpdates }

    func start() {
        controller.startUpdater()
        isStarted = true
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
