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

    @Test func rendersBackupTitle() throws {
        var t = makeActive()
        t = Transfer(
            jobID: 101, operation: .sync, srcFs: "/Users/j/Documents", dstFs: "b2:mac-backup/Documents",
            startedAt: t.startedAt, completedAt: Date(timeIntervalSince1970: 1_700_000_120),
            status: .completed, origin: .backup, nimbusUUID: t.nimbusUUID,
            backup: Transfer.BackupContext(
                backupID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                title: "Documents to B2", trigger: .scheduled,
                isMirrorWithVersions: true, hadRemovalLimit: true
            )
        )
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: t),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-backup"
        )
    }
}
