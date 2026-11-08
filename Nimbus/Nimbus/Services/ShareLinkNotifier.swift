import Foundation
import UserNotifications
import os

/// Shows **"Share link copied"** when Finder's Copy Share Link succeeds.
/// Listens for `ShareLinkSignal`'s Darwin notification from the extension.
/// Respects notification permission: if Nimbus isn't allowed to notify, the
/// link is still on the clipboard and nothing is shown.
@MainActor
final class ShareLinkNotifier {
    static let shared = ShareLinkNotifier()
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "share-links")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in await ShareLinkNotifier.shared.linkCopied() }
            },
            ShareLinkSignal.notificationName as CFString,
            nil,
            .deliverImmediately)
    }

    func linkCopied() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info("Share link copied; notifications not allowed, so no banner")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Share link copied"
        content.body = ShareLinkSignal.lastFileName.map { "Anyone with the link can open “\($0)”." }
            ?? "Anyone with the link can open it."
        do {
            try await center.add(UNNotificationRequest(identifier: "share-link-\(UUID().uuidString)",
                                                       content: content, trigger: nil))
        } catch {
            logger.error("Couldn't show the share-link notification: \((error as NSError).code, privacy: .public)")
        }
    }
}
