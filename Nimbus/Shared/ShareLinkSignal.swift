import Foundation

/// How the File Provider extension tells the app "a share link was just
/// copied", so the app can confirm it with a notification (Finder itself
/// shows nothing). The app is always running when the action works: it
/// hosts the rclone engine the extension talks to.
///
/// The file name goes through the shared app-group defaults; the nudge is a
/// Darwin notification, which carries no payload and is allowed from the
/// sandboxed extension.
enum ShareLinkSignal {
    static let notificationName = "app.casavargas.nimbus.shareLinkCopied"
    private static let nameKey = "lastShareLinkName"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.app.casavargas.nimbus") }

    /// Extension side.
    static func announce(fileName: String) {
        defaults?.set(fileName, forKey: nameKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString), nil, nil, true)
    }

    /// App side: the name from the most recent announcement.
    static var lastFileName: String? { defaults?.string(forKey: nameKey) }
}
