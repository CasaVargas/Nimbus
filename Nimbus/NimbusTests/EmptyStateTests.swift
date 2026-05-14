import Testing
import SwiftUI
@testable import Nimbus

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
        try SnapshotHelpers.assertSnapshot(view, size: CGSize(width: 320, height: 200), named: "EmptyState-no-cta")
    }

    @Test func rendersWithCTA() throws {
        let view = EmptyState(
            icon: "key.slash",
            title: "Sign In Required",
            message: "Reconnect your remote to continue.",
            action: .init(label: "Reconnect Remote", perform: {})
        )
        try SnapshotHelpers.assertSnapshot(view, size: CGSize(width: 320, height: 220), named: "EmptyState-with-cta")
    }
}
