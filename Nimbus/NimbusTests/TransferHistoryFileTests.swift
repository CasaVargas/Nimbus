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
