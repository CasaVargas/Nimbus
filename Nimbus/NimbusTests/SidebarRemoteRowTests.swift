import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("SidebarRemoteRow", .serialized)
@MainActor
struct SidebarRemoteRowTests {
    private func makeRemote(name: String = "gdrive", type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    @Test func rendersConnectedStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .connected,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-connected"
        )
    }

    @Test func rendersAuthNeededStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .authNeeded,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-auth-needed"
        )
    }

    @Test func rendersUnknownStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .unknown,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-unknown"
        )
    }

    @Test func rendersErrorStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .error(reason: "Server returned 500"),
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-error"
        )
    }
}
