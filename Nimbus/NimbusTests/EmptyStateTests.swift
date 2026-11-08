import Testing
import SwiftUI
@testable import Nimbus

/// Rendered through a real hosting window (`assertHostedSnapshot`), not
/// `ImageRenderer`: ImageRenderer draws `ContentUnavailableView` blank, so
/// these fixtures used to be empty images (one test always failed, the
/// other "passed" by matching blank against blank). The opaque window
/// background matters too: the hosted capture is transparent, and dark-mode
/// text on a transparent image is invisible.
@Suite("EmptyState", .serialized)
@MainActor
struct EmptyStateTests {
    @Test func rendersTitleAndMessage() throws {
        let view = EmptyState(
            icon: "folder",
            title: "Empty Folder",
            message: "Drop files here.",
            action: nil
        )
        try SnapshotHelpers.assertHostedSnapshot(view.background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 320, height: 200), named: "EmptyState-no-cta")
    }

    @Test func rendersWithCTA() throws {
        let view = EmptyState(
            icon: "key.slash",
            title: "Sign In Required",
            message: "Reconnect your remote to continue.",
            action: .init(label: "Reconnect Remote", perform: {})
        )
        try SnapshotHelpers.assertHostedSnapshot(view.background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 320, height: 220), named: "EmptyState-with-cta")
    }
}
