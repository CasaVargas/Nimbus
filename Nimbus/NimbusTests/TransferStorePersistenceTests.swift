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

    @Test func failedOlderSaveDrainsTheNewestQueuedSnapshot() async throws {
        let history = SuspendedFirstSaveThenFailingHistory()
        let store = TransferStore(history: history)
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")
        store.addTransfer(jobId: 2, operation: .copy, srcFs: "a:", dstFs: "b:")

        let firstCompletion = Task { await store.completeTransfer(jobId: 1) }
        #expect(await history.waitForFirstSave(timeout: .seconds(1)))
        await store.completeTransfer(jobId: 2)
        await history.releaseFirstSave()
        await firstCompletion.value

        #expect(await history.saveCount == 2)
        let reloaded = try await history.load()
        #expect(Set(reloaded.compactMap(\.jobID)) == [1, 2])
    }

    @Test func settingsRetentionChangeAppliesWithoutRestart() async {
        let history = HistorySpy(records: [
            finishedRecord(jobID: 1, completedAt: .distantPast),
            finishedRecord(jobID: 2, completedAt: Date()),
        ])
        let store = TransferStore(history: history)
        await store.restoreHistory(retention: .forever)
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.transferHistoryRetention = .sevenDays

        await store.applyRetention(from: settings)

        #expect(store.completedTransfers.map(\.jobID) == [2])
        #expect(await history.savedRecords.map(\.jobID) == [2])
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

    private func isolatedDefaults() -> UserDefaults {
        let name = "NimbusTests.TransferStorePersistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
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

private actor SuspendedFirstSaveThenFailingHistory: TransferHistoryPersisting {
    private var records: [TransferRecord] = []
    private(set) var saveCount = 0
    private var firstSaveRelease: CheckedContinuation<Void, Never>?
    private var firstSaveWasReleased = false

    func load() async throws -> [TransferRecord] {
        records
    }

    func save(_ records: [TransferRecord]) async throws {
        saveCount += 1
        if saveCount == 1 {
            await withCheckedContinuation { continuation in
                if firstSaveWasReleased {
                    continuation.resume()
                } else {
                    firstSaveRelease = continuation
                }
            }
            throw TestSaveError.firstSave
        }
        self.records = records
    }

    func quarantineCorruptFile() async {}

    func waitForFirstSave(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while saveCount == 0 {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }

    func releaseFirstSave() {
        firstSaveWasReleased = true
        firstSaveRelease?.resume()
        firstSaveRelease = nil
    }
}

private enum TestSaveError: Error {
    case firstSave
}
