import Foundation
import Testing
@testable import Nimbus

@Suite("TransferStorePersistence", .serialized)
@MainActor
struct TransferStorePersistenceTests {
    @Test func activeTransfersAreNeverPersisted() async {
        let history = HistorySpy()
        let store = TransferStore(history: history)

        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")

        #expect(await history.savedRecords.isEmpty)
    }

    @Test func restoredAndNewJobsWithSameRcloneIDHaveDistinctIdentity() async {
        let history = HistorySpy(records: [finishedRecord(jobID: 1)])
        let store = TransferStore(history: history)
        await store.restoreHistory(retention: .forever)

        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")

        #expect(Set(store.transfers.map(\.id)).count == 2)
        #expect(store.transfers.map(\.jobID) == [1, 1])
    }

    @Test func completionPersistsOnlyTerminalHistory() async {
        let history = HistorySpy()
        let store = TransferStore(history: history)
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")

        await store.completeTransfer(jobId: 1)

        #expect(await history.savedRecords.count == 1)
        #expect(await history.savedRecords.first?.outcome == .completed)
    }

    @Test func applyingRetentionDoesNotRemoveActiveTransfers() async {
        let history = HistorySpy(records: [
            finishedRecord(jobID: 1, completedAt: .distantPast),
            finishedRecord(jobID: 2, completedAt: Date()),
        ])
        let store = TransferStore(history: history)
        await store.restoreHistory(retention: .forever)
        store.addTransfer(jobId: 3, operation: .sync, srcFs: "a:", dstFs: "b:")

        await store.applyRetention(.sevenDays)

        #expect(store.activeTransfers.map(\.jobID) == [3])
        #expect(store.completedTransfers.map(\.jobID) == [2])
    }

    @Test func untilQuitSkipsHistoryLoadAndSave() async {
        let history = HistorySpy(records: [finishedRecord(jobID: 1)])
        let store = TransferStore(history: history)

        await store.restoreHistory(retention: .untilQuit)
        store.addTransfer(jobId: 2, operation: .copy, srcFs: "a:", dstFs: "b:")
        await store.completeTransfer(jobId: 2)

        #expect(store.transfers.map(\.jobID) == [2])
        #expect(await history.loadCount == 0)
        #expect(await history.savedRecords.isEmpty)
    }

    private func finishedRecord(jobID: Int, completedAt: Date = Date()) -> TransferRecord {
        TransferRecord(
            id: UUID(),
            jobID: jobID,
            operation: .copy,
            source: "source:",
            destination: "destination:",
            startedAt: completedAt.addingTimeInterval(-60),
            completedAt: completedAt,
            outcome: .completed,
            origin: .manual
        )
    }
}

private actor HistorySpy: TransferHistoryPersisting {
    private(set) var records: [TransferRecord]
    private(set) var savedRecords: [TransferRecord] = []
    private(set) var loadCount = 0

    init(records: [TransferRecord] = []) {
        self.records = records
    }

    func load() async throws -> [TransferRecord] {
        loadCount += 1
        return records
    }

    func save(_ records: [TransferRecord]) async throws {
        savedRecords = records
    }

    func quarantineCorruptFile() async {}
}
