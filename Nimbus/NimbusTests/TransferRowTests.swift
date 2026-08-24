import Testing
import SwiftUI
import Foundation
@testable import Nimbus

@Suite("TransferRow", .serialized)
@MainActor
struct TransferRowTests {
    private func makeActive() -> Transfer {
        Transfer(
            jobID: 100,
            operation: .copy,
            srcFs: "gdrive:/Photos/IMG_4827.heic",
            dstFs: "s3:/Backup/IMG_4827.heic",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: nil,
            status: .active,
            origin: .crossRemoteDrop,
            nimbusUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            progress: 0.47
        )
    }

    @Test func rendersActiveWithProgress() throws {
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: makeActive()),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-active"
        )
    }

    @Test func rendersCompletedRow() throws {
        var t = makeActive()
        t.status = .completed
        t.completedAt = Date(timeIntervalSince1970: 1_700_000_120)
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: t),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-completed"
        )
    }

    @Test func rendersFailedRow() throws {
        var t = makeActive()
        t.status = .failed("Network timeout")
        t.completedAt = Date(timeIntervalSince1970: 1_700_000_120)
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: t),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-failed"
        )
    }
}
