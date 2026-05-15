import Testing
import SwiftUI
import Foundation
@testable import Nimbus

@Suite("MountRow", .serialized)
@MainActor
struct MountRowTests {
    private func makeConfig() -> MountConfig {
        MountConfig(
            remote: "gdrive:",
            mountPoint: "/Users/me/Cloud/gdrive",
            vfsMode: .readWrite,
            autoMount: false,
            backend: .nfs
        )
    }

    @Test func rendersOffState() throws {
        let view = MountRow(
            config: makeConfig(), state: .off,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-off"
        )
    }

    @Test func rendersMountingState() throws {
        let view = MountRow(
            config: makeConfig(), state: .mounting,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-mounting"
        )
    }

    @Test func rendersOnState() throws {
        let view = MountRow(
            config: makeConfig(), state: .on,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-on"
        )
    }

    @Test func rendersErrorState() throws {
        let view = MountRow(
            config: makeConfig(), state: .error(reason: "Permission denied"),
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-error"
        )
    }
}
