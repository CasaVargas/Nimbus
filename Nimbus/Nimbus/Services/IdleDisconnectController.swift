import AppKit
import Foundation
import Observation
import os

/// The pure rule: sleep once nothing has used the engine for `timeout`.
enum IdleDisconnectPolicy {
    static func shouldSleep(timeout: TimeInterval?, lastActivity: Date, now: Date, isBusy: Bool) -> Bool {
        guard let timeout, !isBusy else { return false }
        return now.timeIntervalSince(lastActivity) >= timeout
    }
}

/// Stops the rclone engine after the user's idle timeout and starts it again
/// on the next use (spec: 2026-11-14-dock-idle-storage-design.md).
///
/// Activity is a visible Nimbus window, a transfer or backup, a mounted
/// network drive, or a wake ping from the File Provider extension (Finder
/// used a drive, `NimbusWake`). Any of those also wakes a sleeping engine.
@MainActor
@Observable
final class IdleDisconnectController {
    /// For callers outside the view tree (Shortcuts).
    static weak var current: IdleDisconnectController?

    struct Activity {
        var hasVisibleWindow: @MainActor () -> Bool
        var hasActiveWork: @MainActor () -> Bool
    }

    @ObservationIgnored private let daemon: RcloneDaemon
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let activity: Activity
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "idle")
    /// Called right after the engine goes to sleep (pause pollers).
    @ObservationIgnored var onSleep: (@MainActor () -> Void)?

    private(set) var lastActivity: Date

    static let tickInterval: Duration = .seconds(15)
    static let wakeNotification = Notification.Name("app.casavargas.nimbus.finderWake")

    init(daemon: RcloneDaemon, settings: AppSettings, activity: Activity, now: @escaping () -> Date = Date.init) {
        self.daemon = daemon
        self.settings = settings
        self.activity = activity
        self.now = now
        lastActivity = now()
    }

    /// Starts the tick and the wake listeners once.
    func start() {
        guard tickTask == nil else { return }
        Self.current = self
        Self.observeDarwinWake()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            Self.wakeNotification,
            NSWindow.didBecomeKeyNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            })
        }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    /// Something used the engine: restart the clock, and start the engine
    /// if it's asleep.
    func wake() {
        lastActivity = now()
        guard daemon.status == .asleep, wakeTask == nil else { return }
        wakeTask = Task { @MainActor [weak self] in
            await self?.wakeAndWait()
            self?.wakeTask = nil
        }
    }

    /// Wakes the engine and returns once it's connected (or failed).
    func wakeAndWait() async {
        lastActivity = now()
        guard daemon.status == .asleep else { return }
        await daemon.wake(
            binaryPath: settings.rcloneBinaryPath,
            bandwidthLimit: settings.bandwidthLimit,
            concurrentTransfers: settings.concurrentTransfers
        )
    }

    func tick() {
        let busy = activity.hasVisibleWindow() || activity.hasActiveWork()
        if busy {
            lastActivity = now()
            if daemon.status == .asleep { wake() }
            return
        }
        guard daemon.status == .connected,
              IdleDisconnectPolicy.shouldSleep(
                timeout: settings.idleDisconnect.interval,
                lastActivity: lastActivity, now: now(), isBusy: false
              ) else { return }
        logger.info("Idle for \(self.settings.idleDisconnect.rawValue) min; stopping rclone")
        daemon.sleep()
        onSleep?()
    }

    // MARK: Darwin wake ping from the extension

    private static var isObservingDarwin = false

    private static func observeDarwinWake() {
        guard !isObservingDarwin else { return }
        isObservingDarwin = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: IdleDisconnectController.wakeNotification, object: nil)
                }
            },
            NimbusWake.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Whether a Nimbus window (main, Settings, the menu bar companion) is
    /// on screen. The status item's own window can't become key, so it
    /// doesn't count.
    static func hasVisibleWindow() -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeKey && $0.occlusionState.contains(.visible) }
    }
}
