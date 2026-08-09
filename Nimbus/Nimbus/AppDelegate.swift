import AppKit
import CoreServices.AE  // for keyAEPropData / keyAELaunchedAsLogInItem

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when launchd started us at login (vs. user-initiated launch).
    /// Read once in applicationWillFinishLaunching.
    private(set) var wasLaunchedAtLogin: Bool = false

    /// Async cleanup to run before the process dies (set by NimbusApp at
    /// startup): unmount NFS volumes, stop `rclone serve nfs` children and
    /// the RC daemon. Covers ⌘Q, the MenuBarExtra Quit, and logout.
    var shutdownHandler: (@MainActor () async -> Void)?
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdownHandler, !isTerminating else { return .terminateNow }
        isTerminating = true
        Task { @MainActor in
            await shutdownHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
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
