import AppKit
import CoreServices.AE  // for keyAEPropData / keyAELaunchedAsLogInItem
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when launchd started us at login (vs. user-initiated launch).
    /// Read once in applicationWillFinishLaunching.
    private(set) var wasLaunchedAtLogin: Bool = false

    /// Async cleanup to run before the process dies (set by NimbusApp at
    /// startup): unmount NFS volumes, stop `rclone serve nfs` children and
    /// the RC daemon. Covers ⌘Q, the MenuBarExtra Quit, and logout.
    var shutdownHandler: (@MainActor () async -> Void)?
    private var isTerminating = false

    /// True while a backup is running or queued (set by NimbusApp). When it
    /// returns true, quitting asks first.
    var shouldConfirmQuit: (@MainActor () -> Bool)?
    /// Opens the Backups screen, on a job when the notification names one.
    var onBackupNotificationClick: (@MainActor (UUID?) -> Void)?
    /// Logout and restart post this before asking apps to quit.
    private var isPowerOff = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !isTerminating,
           QuitDecision.make(isBackupRunning: shouldConfirmQuit?() ?? false, isPowerOff: isPowerOff) == .askFirst,
           !confirmQuit() {
            return .terminateCancel
        }
        guard let shutdownHandler, !isTerminating else { return .terminateNow }
        isTerminating = true
        Task { @MainActor in
            await shutdownHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func confirmQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = QuitDecision.alertMessage
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func systemWillPowerOff(_ notification: Notification) {
        isPowerOff = true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification, object: nil
        )
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           let propData = event.paramDescriptor(forKeyword: keyAEPropData),
           propData.enumCodeValue == keyAELaunchedAsLogInItem {
            wasLaunchedAtLogin = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if wasLaunchedAtLogin {
            // Hide all windows and become an accessory app (no Dock icon).
            for window in NSApp.windows {
                window.orderOut(nil)
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Closing the only window must NOT terminate the app — we want the
    /// MenuBarExtra to keep running so the user can reopen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Bring back the Dock icon when reopening from Finder/Spotlight.
            NSApp.setActivationPolicy(.regular)
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// A click on a backup notification opens the Backups screen on that job.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard userInfo[TransferNotificationRequest.backupIDKey] != nil else { return }
        let id = TransferNotificationRequest.backupID(fromUserInfo: userInfo)
        await MainActor.run { onBackupNotificationClick?(id) }
    }
}
