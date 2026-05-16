import Foundation

/// A one-shot request to show a specific path inside a remote. Published by
/// bookmark taps and the `openBrowser` action. Carries a unique `token` so
/// each publication is a distinct value: that makes `.onChange(of:)` fire even
/// when the same bookmark (same remote + path) is tapped again. For a
/// cross-remote jump the destination `BrowserView` is recreated (`.id(remote)`)
/// and reads the path via `initialPath`; for an in-remote jump the live view's
/// `.onChange` applies it. Equatable/Sendable to satisfy `.onChange` + strict
/// concurrency.
struct BrowseTarget: Equatable, Sendable {
    let remote: String
    let path: String
    private let token = UUID()
}
