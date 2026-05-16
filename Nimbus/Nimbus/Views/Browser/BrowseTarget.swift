import Foundation

/// A request to show a specific path inside a remote. Published by bookmark
/// taps and the `openBrowser` action; consumed by the live `BrowserView` so a
/// jump preserves the running browser instead of recreating it.
struct BrowseTarget: Equatable, Sendable {
    let remote: String
    let path: String
}
