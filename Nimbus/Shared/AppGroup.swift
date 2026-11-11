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
/// A fork signed by another team changes the prefix here, in both
/// `.entitlements` files and in `NSExtensionFileProviderDocumentGroup`
/// (`project.yml` and the extension's `Info.plist`). `AppGroupTests` checks
/// that they agree.
enum AppGroup {
    static let identifier = "53MUTM55LC.app.casavargas.nimbus"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}
