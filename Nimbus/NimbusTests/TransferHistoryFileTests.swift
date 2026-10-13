import Foundation
import Testing
@testable import Nimbus

@Suite("TransferHistoryFile")
struct TransferHistoryFileTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func roundTripsFinishedRecords() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests.TransferHistory.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let record = finishedRecord(completedAt: now)
        let file = TransferHistoryFile(url: url)

        try await file.save([record])

        #expect(try await file.load() == [record])
    }

    @Test func sevenDaysPrunesOlderRecords() {
        let sixDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-6 * 86_400))
        let eightDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-8 * 86_400))

        let kept = TransferHistoryPolicy.prune(
            [sixDaysOld, eightDaysOld],
            retention: .sevenDays,
            now: now
        )

        #expect(kept == [sixDaysOld])
    }

    @Test func corruptHistoryIsQuarantined() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests.TransferHistory.\(UUID().uuidString).json")
        try Data("not JSON".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = TransferHistoryFile(url: url)

        await file.quarantineCorruptFile()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptedRestoreQuarantinesAndPreservesOriginalBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests.TransferHistory.\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("transfer-history-v1.json")
        let corruptData = Data("not JSON".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try corruptData.write(to: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = await MainActor.run {
            TransferStore(history: TransferHistoryFile(url: url))
        }

        await store.restoreHistory(retention: .forever)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantinedName = try #require(names.first { $0.hasPrefix("transfer-history-v1.corrupt-") })
        let quarantinedURL = directory.appendingPathComponent(quarantinedName)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: quarantinedURL) == corruptData)
    }

    @Test func unsupportedFutureSchemaIsPreservedDuringRestore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests.TransferHistory.\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("transfer-history-v1.json")
        let futureData = Data(#"{"version":99,"entries":[]}"#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try futureData.write(to: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = await MainActor.run {
            TransferStore(history: TransferHistoryFile(url: url))
        }

        await store.restoreHistory(retention: .forever)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == futureData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }

    @Test func eachRetentionModeUsesItsDocumentedBoundary() {
        let sixDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-6 * 86_400))
        let eightDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-8 * 86_400))
        let twentyNineDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-29 * 86_400))
        let thirtyOneDaysOld = finishedRecord(completedAt: now.addingTimeInterval(-31 * 86_400))
        let records = [sixDaysOld, eightDaysOld, twentyNineDaysOld, thirtyOneDaysOld]

        #expect(TransferHistoryPolicy.prune(records, retention: .sevenDays, now: now) == [sixDaysOld])
        #expect(TransferHistoryPolicy.prune(records, retention: .thirtyDays, now: now) == [sixDaysOld, eightDaysOld, twentyNineDaysOld])
        #expect(TransferHistoryPolicy.prune(records, retention: .forever, now: now) == records)
        #expect(TransferHistoryPolicy.prune(records, retention: .untilQuit, now: now) == records)
    }

    private func finishedRecord(completedAt: Date) -> TransferRecord {
        TransferRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            jobID: 7,
            operation: .copy,
            source: "source:",
            destination: "destination:",
            startedAt: now.addingTimeInterval(-60),
            completedAt: completedAt,
            outcome: .completed,
            origin: .manual
        )
    }
}
