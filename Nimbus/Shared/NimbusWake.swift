import Foundation

/// How Finder use reaches the app when its rclone engine is asleep or the
/// app isn't running (idle disconnect, `IdleDisconnectController`).
///
/// - The extension posts a Darwin notification whenever Finder uses a drive;
///   the app counts it as activity and wakes a sleeping engine.
/// - When the app isn't running, the extension writes a launch marker and
///   opens the app; a launch with a fresh marker starts hidden, like a login
///   launch. `finder-wake.json` carries the user's "Open Nimbus from Finder"
///   choice, since the extension can't read the app's preferences.
enum NimbusWake {
    /// Team-prefixed like the app group, which a sandboxed process may post.
    static let notificationName = "\(AppGroup.identifier).wake"

    static let prefsFileName = "finder-wake.json"
    static let launchMarkerFileName = "finder-launch-request"
    /// A marker older than this did not cause the current launch.
    static let launchMarkerLifetime: TimeInterval = 60

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil, nil, true
        )
    }

    // MARK: Prefs

    static func encodePrefs(opensApp: Bool) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["opensApp": opensApp])) ?? Data()
    }

    /// Missing or unreadable prefs mean the default: on.
    static func decodeOpensApp(_ data: Data?) -> Bool {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["opensApp"] as? Bool else { return true }
        return value
    }

    static func readOpensApp(in container: URL?) -> Bool {
        guard let container else { return true }
        return decodeOpensApp(try? Data(contentsOf: container.appendingPathComponent(prefsFileName)))
    }

    static func writePrefs(opensApp: Bool, in container: URL?) {
        guard let container else { return }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try? encodePrefs(opensApp: opensApp)
            .write(to: container.appendingPathComponent(prefsFileName), options: .atomic)
    }

    // MARK: Launch marker

    static func writeLaunchMarker(in container: URL?, now: Date = Date()) {
        guard let container else { return }
        let text = String(now.timeIntervalSince1970)
        try? Data(text.utf8).write(to: container.appendingPathComponent(launchMarkerFileName), options: .atomic)
    }

    static func isFresh(markerData: Data?, now: Date) -> Bool {
        guard let markerData,
              let text = String(data: markerData, encoding: .utf8),
              let stamp = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        let age = now.timeIntervalSince1970 - stamp
        return age >= -5 && age <= launchMarkerLifetime
    }

    /// True when the extension asked for this launch. Removes the marker so
    /// a later ordinary launch isn't mistaken for one.
    static func consumeLaunchMarker(in container: URL?, now: Date = Date()) -> Bool {
        guard let container else { return false }
        let url = container.appendingPathComponent(launchMarkerFileName)
        let data = try? Data(contentsOf: url)
        guard data != nil else { return false }
        try? FileManager.default.removeItem(at: url)
        return isFresh(markerData: data, now: now)
    }
}
