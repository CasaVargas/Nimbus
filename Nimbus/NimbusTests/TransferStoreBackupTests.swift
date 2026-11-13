import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// History spy that records saves and never touches disk.
private actor SavedHistory: TransferHistoryPersisting {
    private(set) var saved: [[TransferRecord]] = []
    func load() async throws -> [TransferRecord] { [] }
    func save(_ records: [TransferRecord]) async throws { saved.append(records) }
    func quarantineCorruptFile() async {}
}

/// The notification permission prompt nobody answers: delivery never returns.
private struct UnansweredPromptNotifier: TransferNotifying {
    func authorizationStatus() async -> NotificationAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> Bool { false }
    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async {
        try? await Task.sleep(for: .seconds(3600))
    }
}

enum BackupFixtures {
    static func job(id: Int, success: Bool, error: String = "") -> Job {
        let json = """
        {"id": \(id), "group": "job/\(id)", "startTime": "", "endTime": "", "error": "\(error)",
         "finished": true, "success": \(success), "duration": 1}
        """
        return try! JSONDecoder().decode(Job.self, from: Data(json.utf8))
    }

    static func stats(transfers: Int, deletes: Int, renames: Int, errors: Int = 0, bytes: Int64 = 1000,
                      lastError: String? = nil) -> StatsResponse {
        let lastErrorField = lastError.map { #""lastError": "\#($0)","# } ?? ""
        let json = """
        {\(lastErrorField) "speed": 0, "bytes": \(bytes), "errors": \(errors), "checks": 0, "transfers": \(transfers),
         "deletes": \(deletes), "renames": \(renames), "elapsedTime": 1, "totalBytes": \(bytes),
         "totalTransfers": \(transfers), "totalChecks": 0}
        """
        return try! JSONDecoder().decode(StatsResponse.self, from: Data(json.utf8))
    }
}

@Suite("TransferStoreBackup", .serialized)
@MainActor
struct TransferStoreBackupTests {
    let start = Date(timeIntervalSince1970: 1_794_000_000)
    let end = Date(timeIntervalSince1970: 1_794_000_060)
    let backupID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    private func context(mirrorWithVersions: Bool = true, hadRemovalLimit: Bool = true) -> Transfer.BackupContext {
        Transfer.BackupContext(
            backupID: backupID, title: "Documents to B2", trigger: .manual,
            isMirrorWithVersions: mirrorWithVersions, hadRemovalLimit: hadRemovalLimit
        )
    }

    // MARK: - Pure summary / outcome

    /// Measured on rclone 1.76: with a backup dir, `deletes` counts files
    /// removed from the destination and `renames` counts every move into the
    /// backup dir (replaced + removed).
    @Test func summaryWithVersionsSplitsReplacedFromRemoved() {
        let summary = TransferStore.summary(
            trigger: .scheduled, startedAt: start, finishedAt: end, outcome: .completed,
            stats: BackupFixtures.stats(transfers: 12, deletes: 1, renames: 3, bytes: 48_213_004),
            isMirrorWithVersions: true
        )
        #expect(summary.copied == 12)
        #expect(summary.replaced == 2)
        #expect(summary.removed == 1)
        #expect(summary.errors == 0)
        #expect(summary.bytes == 48_213_004)
        #expect(summary.trigger == .scheduled)
        #expect(summary.startedAt == start)
        #expect(summary.finishedAt == end)
    }

    @Test func summaryCountsDeletesWithoutVersions() {
        let summary = TransferStore.summary(
            trigger: .manual, startedAt: start, finishedAt: end, outcome: .completed,
            stats: BackupFixtures.stats(transfers: 3, deletes: 2, renames: 5),
            isMirrorWithVersions: false
        )
        #expect(summary.removed == 2)
        #expect(summary.replaced == 0)
    }

    @Test func summaryWithoutStatsIsZero() {
        let summary = TransferStore.summary(
            trigger: .manual, startedAt: start, finishedAt: end, outcome: .cancelled,
            stats: nil, isMirrorWithVersions: true
        )
        #expect(summary.copied == 0 && summary.removed == 0 && summary.bytes == 0)
        #expect(summary.outcome == .cancelled)
    }

    /// rclone 1.76: a run stopped by MaxDelete fails with "failed to delete N
    /// files" and core/stats.lastError "--max-delete threshold reached".
    @Test func limitHitFromMaxDeleteLastError() {
        #expect(TransferStore.backupOutcome(jobError: "failed to delete 2 files", hadRemovalLimit: true,
                                            lastError: "--max-delete threshold reached") == .limitHit)
    }

    /// Any other delete failure (permissions, object lock) uses the same job
    /// error; it must not read as the removal limit.
    @Test func permissionDeniedDeleteIsAFailureWithTheRealReason() {
        #expect(TransferStore.backupOutcome(jobError: "failed to delete 1 files", hadRemovalLimit: true,
                                            lastError: "remove /x/locked.txt: permission denied")
            == .failed("remove /x/locked.txt: permission denied"))
    }

    @Test func plainFailureStaysFailure() {
        #expect(TransferStore.backupOutcome(jobError: "directory not found", hadRemovalLimit: true, lastError: nil)
            == .failed("directory not found"))
        #expect(TransferStore.backupOutcome(jobError: "failed to delete 2 files", hadRemovalLimit: false,
                                            lastError: "--max-delete threshold reached")
            == .failed("--max-delete threshold reached"))
    }

    // MARK: - Finish flow

    /// Found live on 2026-11-10: a failed catch-up run sat on "Backing up…
    /// 0%" for good, because finishing waited on the permission prompt.
    @Test(.timeLimit(.minutes(1)))
    func unansweredNotificationPromptDoesNotHoldUpAFailedBackup() async throws {
        let history = SavedHistory()
        let store = TransferStore(history: history, notifications: UnansweredPromptNotifier())
        var received: [(UUID, BackupRunSummary)] = []
        store.onBackupFinished = { id, summary in received.append((id, summary)) }
        store.addTransfer(jobId: 41, operation: .sync, srcFs: "/Users/j/Documents", dstFs: "b2:mac",
                          origin: .backup, backup: context())

        await store.handleFinished(jobID: 41, job: BackupFixtures.job(id: 41, success: false, error: "rename failed"),
                                   stats: nil, now: end)

        #expect(received.count == 1)
        #expect(store.activeTransfers.isEmpty)
        #expect(await history.saved.count == 1)
    }

    /// The same wait froze plain transfers and the poll loop behind them.
    @Test(.timeLimit(.minutes(1)))
    func unansweredNotificationPromptDoesNotHoldUpAFailedTransfer() async {
        let history = SavedHistory()
        let store = TransferStore(history: history, notifications: UnansweredPromptNotifier())
        store.addTransfer(jobId: 7, operation: .copy, srcFs: "a:", dstFs: "b:")

        await store.failTransfer(jobId: 7, error: "Timed out")

        #expect(store.activeTransfers.isEmpty)
        #expect(await history.saved.count == 1)
    }

    @Test func finishingBackupStoresSummaryAndCallsHook() async throws {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var received: [(UUID, BackupRunSummary)] = []
        store.onBackupFinished = { id, summary in received.append((id, summary)) }
        store.addTransfer(jobId: 41, operation: .sync, srcFs: "/Users/j/Documents", dstFs: "b2:mac",
                          origin: .backup, backup: context())

        await store.handleFinished(
            jobID: 41, job: BackupFixtures.job(id: 41, success: true),
            stats: BackupFixtures.stats(transfers: 12, deletes: 1, renames: 2),
            now: end
        )

        let transfer = try #require(store.transfers.first)
        guard case .completed = transfer.status else {
            Issue.record("expected completed, got \(transfer.status)")
            return
        }
        #expect(transfer.summary?.copied == 12)
        #expect(transfer.summary?.removed == 1)
        #expect(transfer.summary?.replaced == 1)
        #expect(transfer.record?.summary == transfer.summary)
        #expect(transfer.record?.backupID == backupID)
        #expect(transfer.record?.title == "Documents to B2")
        #expect(received.count == 1)
        #expect(received.first?.0 == backupID)
        #expect(received.first?.1.outcome == .completed)
    }

    @Test func limitHitBackupFailsWithLimitOutcome() async throws {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var outcomes: [BackupRunSummary.Outcome] = []
        store.onBackupFinished = { _, summary in outcomes.append(summary.outcome) }
        store.addTransfer(jobId: 42, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())

        await store.handleFinished(
            jobID: 42, job: BackupFixtures.job(id: 42, success: false, error: "failed to delete 4 files"),
            stats: BackupFixtures.stats(transfers: 0, deletes: 2, renames: 0, lastError: "--max-delete threshold reached"),
            now: end
        )

        #expect(outcomes == [.limitHit])
        guard case .failed = try #require(store.transfers.first).status else {
            Issue.record("limit hit should read as a failed transfer")
            return
        }
    }

    @Test func plainTransferFinishDoesNotCallHook() async {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var calls = 0
        store.onBackupFinished = { _, _ in calls += 1 }
        store.addTransfer(jobId: 43, operation: .copy, srcFs: "a:", dstFs: "b:")
        await store.handleFinished(jobID: 43, job: BackupFixtures.job(id: 43, success: true), stats: nil, now: end)
        #expect(calls == 0)
        #expect(store.transfers.first?.summary == nil)
    }

    @Test func cancellingBackupCallsHookWithCancelled() async {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var outcomes: [BackupRunSummary.Outcome] = []
        store.onBackupFinished = { _, summary in outcomes.append(summary.outcome) }
        store.addTransfer(jobId: 44, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())
        await store.cancelTransfer(jobId: 44)
        #expect(outcomes == [.cancelled])
    }

    // MARK: - Lost jobs

    @Test func lostJobFinishesBackupAsFailed() async throws {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var outcomes: [BackupRunSummary.Outcome] = []
        store.onBackupFinished = { _, summary in outcomes.append(summary.outcome) }
        store.addTransfer(jobId: 50, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())

        await store.handlePollFailure(jobID: 50, error: RcloneError.requestFailed(status: 500, message: "job not found"), now: end)

        #expect(outcomes == [.failed(TransferStore.lostRunMessage)])
        guard case .failed = try #require(store.transfers.first).status else {
            Issue.record("a lost job must not stay active")
            return
        }
    }

    @Test func transientPollErrorKeepsTransferActive() async {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var calls = 0
        store.onBackupFinished = { _, _ in calls += 1 }
        store.addTransfer(jobId: 51, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())
        await store.handlePollFailure(jobID: 51, error: URLError(.timedOut), now: end)
        #expect(calls == 0)
        #expect(store.activeTransfers.count == 1)
    }

    @Test func abandonActiveTransfersFailsEveryActiveRun() async {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        var calls = 0
        store.onBackupFinished = { _, _ in calls += 1 }
        store.addTransfer(jobId: 1, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())
        store.addTransfer(jobId: 2, operation: .copy, srcFs: "a:", dstFs: "b:")
        await store.abandonActiveTransfers()
        #expect(store.activeTransfers.isEmpty)
        #expect(calls == 1)
    }

    // MARK: - Filter

    @Test func backupsFilterShowsOnlyBackups() {
        let store = TransferStore(history: SavedHistory(), retention: .forever)
        store.addTransfer(jobId: 1, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .backup, backup: context())
        store.addTransfer(jobId: 2, operation: .sync, srcFs: "a:", dstFs: "b:", origin: .copySyncJob)
        let shown = store.transfers.filter(TransferFilter.backups.matches)
        #expect(shown.map(\.jobID) == [1])
        #expect(TransferFilter.backups.displayName == "Backups")
    }
}

@Suite("TransferHistoryV2")
struct TransferHistoryV2Tests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests.TransferHistoryV2.\(UUID().uuidString).json")
    }

    private func record(backup: Bool) -> TransferRecord {
        TransferRecord(
            id: UUID(), jobID: 7, operation: .sync, source: "/Users/j/Documents", destination: "b2:mac",
            startedAt: Date(timeIntervalSince1970: 1_794_000_000),
            completedAt: Date(timeIntervalSince1970: 1_794_000_060),
            outcome: .completed, origin: backup ? .backup : .manual,
            backupID: backup ? UUID() : nil,
            title: backup ? "Documents to B2" : nil,
            summary: backup ? BackupRunSummary(
                startedAt: Date(timeIntervalSince1970: 1_794_000_000),
                finishedAt: Date(timeIntervalSince1970: 1_794_000_060),
                trigger: .manual, outcome: .completed, copied: 1, replaced: 0, removed: 0, errors: 0, bytes: 5
            ) : nil
        )
    }

    private func version(at url: URL) throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["version"] as? Int
    }

    @Test func v1HistoryStillLoads() async throws {
        let url = url()
        defer { try? FileManager.default.removeItem(at: url) }
        let v1 = #"""
        {"version": 1, "records": [{"id": "00000000-0000-0000-0000-000000000001", "jobID": 7,
          "operation": "copy", "source": "a:", "destination": "b:",
          "startedAt": 700000000, "completedAt": 700000060,
          "outcome": {"completed": {}}, "origin": "manual"}]}
        """#
        try Data(v1.utf8).write(to: url)
        let records = try await TransferHistoryFile(url: url).load()
        #expect(records.count == 1)
        #expect(records.first?.backupID == nil)
        #expect(records.first?.summary == nil)
    }

    @Test func backupRecordRoundTripsInV2() async throws {
        let url = url()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = TransferHistoryFile(url: url)
        let record = record(backup: true)
        try await file.save([record])
        #expect(try version(at: url) == 2)
        #expect(try await file.load() == [record])
    }

    @Test func savedFileStaysVersion1WithoutBackups() async throws {
        let url = url()
        defer { try? FileManager.default.removeItem(at: url) }
        try await TransferHistoryFile(url: url).save([record(backup: false)])
        #expect(try version(at: url) == 1)
    }
}
