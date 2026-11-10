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

    // MARK: Text

    private func config(_ backend: MountBackend, mountPoint: String) -> MountConfig {
        MountConfig(remote: "Personal:", mountPoint: mountPoint, vfsMode: .readWrite, autoMount: false, backend: backend)
    }

    @Test func inACloudPaneRowsSayWhatTheSwitchDoes() {
        let finder = config(.fileProvider, mountPoint: "")
        let volume = config(.nfs, mountPoint: NSHomeDirectory() + "/Cloud/Personal")
        #expect(MountRowText.title(for: finder, inCloudPane: true) == "Show in Finder")
        #expect(MountRowText.title(for: volume, inCloudPane: true) == "Mount as a network volume")
        #expect(MountRowText.subtitle(for: volume, inCloudPane: true) == "A disk any app can open, at ~/Cloud/Personal")
        // No rclone syntax ("Personal:") in either line.
        for row in [finder, volume] {
            #expect(!MountRowText.title(for: row, inCloudPane: true).contains(":"))
            #expect(!MountRowText.subtitle(for: row, inCloudPane: true).contains("Personal:"))
        }
    }

    @Test func outsideACloudPaneRowsKeepTheCloudName() {
        #expect(MountRowText.title(for: config(.fileProvider, mountPoint: ""), inCloudPane: false) == "Personal")
        #expect(MountRowText.title(for: config(.nfs, mountPoint: "/Users/me/Cloud/gdrive"), inCloudPane: false) == "gdrive")
    }
}
