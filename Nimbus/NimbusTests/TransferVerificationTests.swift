import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// History spy that never touches disk.
private actor NullHistory: TransferHistoryPersisting {
    private(set) var saved: [[TransferRecord]] = []
    func load() async throws -> [TransferRecord] { [] }
    func save(_ records: [TransferRecord]) async throws { saved.append(records) }
    func quarantineCorruptFile() async {}
}

@Suite("TransferVerification")
struct TransferVerificationTests {
    @Test func sharedHashIsVerifiedWithRclonesPick() {
        // Local lists every hash; rclone uses the first one Drive also has.
        let local = ["md5", "sha1", "whirlpool", "crc32", "sha256"]
        #expect(TransferVerification.infer(sourceHashes: local, destinationHashes: ["sha1", "md5", "sha256"])
            == .verified(hash: "md5"))
        #expect(TransferVerification.infer(sourceHashes: local, destinationHashes: ["quickxor", "sha1"])
            == .verified(hash: "sha1"))
    }

    @Test func noSharedHashIsSizeOnly() {
        #expect(TransferVerification.infer(sourceHashes: ["md5"], destinationHashes: ["quickxor"]) == .sizeOnly)
    }

    @Test func cryptReportsNoHashesSoItIsSizeOnly() {
        // rclone 1.76: `:crypt` fsinfo Hashes == [].
        #expect(TransferVerification.infer(sourceHashes: ["md5", "sha1"], destinationHashes: []) == .sizeOnly)
        #expect(TransferVerification.infer(sourceHashes: [], destinationHashes: ["md5"]) == .sizeOnly)
    }

    @Test func mismatchMatchesRclonesHashErrorOnly() {
        #expect(TransferVerification.isMismatch(
            #"corrupted on transfer: md5 hashes differ src(Local file system at /x) "a" vs dst(S3 bucket b) "c""#))
        #expect(!TransferVerification.isMismatch("corrupted on transfer: sizes differ 10 vs 12"))
        #expect(!TransferVerification.isMismatch("Network timeout"))
        #expect(!TransferVerification.isMismatch(nil))
    }

    @Test func remoteRoot() {
        #expect(TransferVerification.remoteRoot(of: "Google Drive:Photos/a.jpg") == "Google Drive:")
        #expect(TransferVerification.remoteRoot(of: "s3:") == "s3:")
        #expect(TransferVerification.remoteRoot(of: "/Users/j/Documents") == "/")
        #expect(TransferVerification.remoteRoot(of: "/Users/j/a:b.txt") == "/")
        #expect(TransferVerification.remoteRoot(of: ":s3,provider=AWS:bucket") == ":s3,provider=AWS:bucket")
    }

    @Test func hashDisplayNames() {
        #expect(TransferVerification.displayName(ofHash: "md5") == "MD5")
        #expect(TransferVerification.displayName(ofHash: "quickxor") == "QuickXorHash")
        #expect(TransferVerification.displayName(ofHash: "hidrive") == "HIDRIVE")
    }

    @Test func recordRoundTripsAndOldRecordsDecode() throws {
        let record = TransferRecord(
            id: UUID(), jobID: 1, operation: .copy, source: "/a", destination: "s3:b",
            startedAt: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 1),
            outcome: .completed, origin: .manual, verification: .verified(hash: "md5")
        )
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(TransferRecord.self, from: data) == record)

        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old.removeValue(forKey: "verification")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        #expect(try JSONDecoder().decode(TransferRecord.self, from: oldData).verification == nil)
    }
}

@Suite("TransferStore verification", .serialized)
@MainActor
struct TransferStoreVerificationTests {
    private func store(jobID: Int) -> TransferStore {
        let store = TransferStore(history: NullHistory())
        store.addTransfer(jobId: jobID, operation: .copy, srcFs: "/Users/j/a.txt", dstFs: "s3:bucket/a.txt")
        return store
    }

    @Test func successWithSharedHashIsVerified() async {
        let s = store(jobID: 7)
        await s.handleFinished(jobID: 7, job: BackupFixtures.job(id: 7, success: true), stats: nil,
                               verification: .verified(hash: "md5"))
        #expect(s.transfers[0].verification == .verified(hash: "md5"))
        #expect(s.transfers[0].record?.verification == .verified(hash: "md5"))
    }

    @Test func successWithoutSharedHashIsSizeOnly() async {
        let s = store(jobID: 8)
        await s.handleFinished(jobID: 8, job: BackupFixtures.job(id: 8, success: true), stats: nil,
                               verification: .sizeOnly)
        #expect(s.transfers[0].verification == .sizeOnly)
    }

    @Test func lookupFailureLeavesPlainDone() async {
        let s = store(jobID: 9)
        await s.handleFinished(jobID: 9, job: BackupFixtures.job(id: 9, success: true), stats: nil, verification: nil)
        #expect(s.transfers[0].verification == nil)
        guard case .completed = s.transfers[0].status else { Issue.record("not completed"); return }
    }

    @Test func failedOrCancelledNeverVerified() async {
        let s = store(jobID: 10)
        await s.handleFinished(jobID: 10, job: BackupFixtures.job(id: 10, success: false, error: "Network timeout"),
                               stats: nil, verification: .verified(hash: "md5"))
        #expect(s.transfers[0].verification == nil)

        let c = store(jobID: 11)
        await c.cancelTransfer(jobId: 11)
        #expect(c.transfers[0].verification == nil)
    }

    @Test func hashErrorIsMismatch() async {
        let s = store(jobID: 12)
        await s.handleFinished(
            jobID: 12,
            job: BackupFixtures.job(id: 12, success: false, error: "corrupted on transfer: md5 hashes differ"),
            stats: nil
        )
        #expect(s.transfers[0].verification == .mismatch)
        #expect(s.transfers[0].record?.outcome == .failed("corrupted on transfer: md5 hashes differ"))
    }

    @Test func successCannotCarryMismatch() async {
        let s = store(jobID: 13)
        await s.handleFinished(jobID: 13, job: BackupFixtures.job(id: 13, success: true), stats: nil,
                               verification: .mismatch)
        #expect(s.transfers[0].verification == nil)
    }
}
