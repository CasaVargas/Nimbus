import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("RemoteRow", .serialized)
@MainActor
struct RemoteRowTests {
    private func makeRemote(name: String = "gdrive", type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    @Test func rendersConnectedStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .connected,
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-connected"
        )
    }

    @Test func rendersAuthNeededStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .authNeeded,
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-auth-needed"
        )
    }

    @Test func rendersErrorStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .error(reason: "Server returned 500"),
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-error"
        )
    }
}
