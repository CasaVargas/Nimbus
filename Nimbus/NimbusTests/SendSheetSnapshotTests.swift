import Foundation
import RcloneKit
import SwiftUI
import Testing

@testable import Nimbus

@Suite("SendToNimbusSheet", .serialized)
@MainActor
struct SendSheetSnapshotTests {
    private var request: SendRequest {
        SendRequest(items: [
            .init(url: URL(fileURLWithPath: "/tmp/report.pdf"), isDirectory: false, size: 9_400_000),
            .init(url: URL(fileURLWithPath: "/tmp/IMG_2041.heic"), isDirectory: false, size: 3_100_000),
            .init(url: URL(fileURLWithPath: "/tmp/notes.txt"), isDirectory: false, size: 1_700_000),
        ])
    }

    private func sheet(remotes: [String]) -> some View {
        SendToNimbusSheet(
            request: request, remoteNames: remotes, lastRemote: "Google Drive", lastPath: "Inbox",
            client: RcloneClient(), onAddCloud: {}, onSent: { _, _ in }
        )
        .environment(TransferStore())
        .background(DesignSystem.Color.semantic.surface)
    }

    @Test func filled() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            sheet(remotes: ["Google Drive", "OneDrive"]), size: CGSize(width: 480, height: 230),
            named: "SendToNimbus-filled"
        )
    }

    @Test func noClouds() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            sheet(remotes: []), size: CGSize(width: 480, height: 200), named: "SendToNimbus-no-clouds"
        )
    }
}
