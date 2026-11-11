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

    // MARK: - #75 verification pills

    private func completed(_ verification: TransferVerification?, status: TransferStatus = .completed) -> Transfer {
        var t = makeActive()
        t.status = status
        t.completedAt = Date(timeIntervalSince1970: 1_700_000_120)
        t.verification = verification
        return t
    }

    @Test func rendersVerifiedRow() throws {
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: completed(.verified(hash: "md5"))),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-verified"
        )
    }

    @Test func rendersSizeCheckedRow() throws {
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: completed(.sizeOnly)),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-size-checked"
        )
    }

    @Test func rendersChecksumMismatchRow() throws {
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: completed(.mismatch, status: .failed("corrupted on transfer: md5 hashes differ"))),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-checksum-mismatch"
        )
    }

    @Test func tooltipsNameTheCheck() {
        #expect(TransferRow.verifiedHelp(hash: "md5").contains("MD5 checksums"))
        #expect(TransferRow.verifiedHelp(hash: "md5").contains("by size only"))
        #expect(TransferRow.sizeOnlyHelp.contains("sizes only"))
        #expect(TransferRow.mismatchHelp("raw rclone error").hasSuffix("raw rclone error"))
    }
}
