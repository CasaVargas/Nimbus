import Foundation

/// The app group shared by Nimbus and its File Provider extension: pins,
/// cloud capabilities, sync snapshots and the daemon port all live in it.
///
/// The identifier is prefixed with the team ID on purpose. macOS honours a
/// team-prefixed group for any build signed by that team. A `group.`-prefixed
/// one is only honoured when a provisioning profile authorizes it, and a
/// Developer ID build ships without a profile: macOS then drops the
/// entitlement without a word and the sandboxed extension is locked out of
/// the container (0.9.1 and 0.10.0 shipped that way).
///
/// The group comes from the `NIMBUS_APP_GROUP` build setting
/// (`Config/Base.xcconfig`, overridable in `Local.xcconfig`) through the
/// `NimbusAppGroup` Info.plist key, falling back to `defaultIdentifier` when
/// missing or unexpanded.
///
/// `mainBundleID`, the containing app's bundle ID, comes the same way from
/// `NIMBUS_BUNDLE_ID` through the `NimbusBundleID` key, so the extensions can
/// name the app without hardcoding it.
enum AppGroup {
    static let defaultIdentifier = "53MUTM55LC.app.casavargas.nimbus"
    static let defaultMainBundleID = "app.casavargas.nimbus"

    static let identifier = infoValue("NimbusAppGroup") ?? defaultIdentifier
    static let mainBundleID = infoValue("NimbusBundleID") ?? defaultMainBundleID

    /// A build-setting value from Info.plist, or nil if it's missing or
    /// was never expanded.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else { return nil }
        return value
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}
