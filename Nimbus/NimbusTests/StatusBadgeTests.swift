import Testing
import SwiftUI
@testable import Nimbus

@Suite("StatusBadge", .serialized)
@MainActor
struct StatusBadgeTests {
    @Test func rendersLocalPill() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .local),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-local"
        )
    }

    @Test func rendersCloudPill() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .cloud),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-cloud"
        )
    }

    @Test func rendersDownloadingRingAtZeroProgress() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .downloading(progress: 0.0)),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-downloading-0"
        )
    }

    @Test func rendersDownloadingRingAtHalfProgress() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .downloading(progress: 0.5)),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-downloading-50"
        )
    }

    @Test func rendersEvictedPill() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .evicted),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-evicted"
        )
    }

    @Test func rendersErrorPill() throws {
        try SnapshotHelpers.assertSnapshot(
            StatusBadge(state: .error(reason: "Could not authenticate")),
            size: CGSize(width: 90, height: 24),
            named: "StatusBadge-error"
        )
    }

    @Test func accessibilityLabelIncludesProgressForDownloading() {
        let badge = StatusBadge(state: .downloading(progress: 0.47))
        #expect(badge.accessibilityLabelString == "Downloading 47 percent")
    }

    @Test func accessibilityLabelForError() {
        let badge = StatusBadge(state: .error(reason: "Auth failed"))
        #expect(badge.accessibilityLabelString == "Error: Auth failed")
    }
}
