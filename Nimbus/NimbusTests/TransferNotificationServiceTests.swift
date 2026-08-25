import Foundation
import Testing
@testable import Nimbus

@Suite("TransferNotificationService")
struct TransferNotificationServiceTests {
    @Test func failuresOnlySuppressesSuccess() async {
        let center = NotificationCenterSpy()
        let service = TransferNotificationService(center: center)

        await service.deliver(completedRecord, mode: .failuresOnly)

        #expect(await center.requests.isEmpty)
    }

    @Test func failuresOnlyDeliversFailure() async {
        let center = NotificationCenterSpy()
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        let requests = await center.requests
        #expect(requests.count == 1)
        #expect(requests.first?.body == "Copy transfer failed.")
        #expect(!requests.contains { $0.body.contains("source:private/path") })
        #expect(!requests.contains { $0.body.contains("destination:private/path") })
    }

    @Test @MainActor func completedTransitionDeliversExactlyOnce() async {
        let notifier = TransferNotifierSpy()
        let store = TransferStore(history: TransferHistorySpy(), notifications: notifier, notificationMode: .allTransfers)
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "source:", dstFs: "destination:")

        await store.completeTransfer(jobId: 1)
        await store.completeTransfer(jobId: 1)

        #expect(await notifier.deliveredOutcomes == [.completed])
    }

    @Test @MainActor func defaultPolicyNotifiesOnlyFailedTransfers() async {
        let center = NotificationCenterSpy()
        let store = TransferStore(
            history: TransferHistorySpy(),
            notifications: TransferNotificationService(center: center)
        )
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "source:", dstFs: "destination:")
        store.addTransfer(jobId: 2, operation: .sync, srcFs: "source:", dstFs: "destination:")
        store.addTransfer(jobId: 3, operation: .move, srcFs: "source:", dstFs: "destination:")

        await store.completeTransfer(jobId: 1)
        await store.failTransfer(jobId: 2, error: "Timed out")
        await store.cancelTransfer(jobId: 3)

        #expect(await center.requests.count == 1)
    }

    @Test @MainActor func cancelledTransitionDoesNotCallNotifier() async {
        let notifier = TransferNotifierSpy()
        let store = TransferStore(history: TransferHistorySpy(), notifications: notifier)
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "source:", dstFs: "destination:")

        await store.cancelTransfer(jobId: 1)

        #expect(await notifier.deliveredOutcomes.isEmpty)
    }

    @Test @MainActor func restoringTerminalHistoryDoesNotDeliverNotifications() async {
        let notifier = TransferNotifierSpy()
        let history = TransferHistorySpy(records: [completedRecord])
        let store = TransferStore(history: history, notifications: notifier)

        await store.restoreHistory(retention: .sevenDays)

        #expect(await notifier.deliveredOutcomes.isEmpty)
    }

    private var completedRecord: TransferRecord {
        record(outcome: .completed)
    }

    private var failedRecord: TransferRecord {
        record(outcome: .failed("Network unavailable"))
    }

    private func record(outcome: TransferOutcome) -> TransferRecord {
        TransferRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            jobID: 7,
            operation: .copy,
            source: "source:private/path",
            destination: "destination:private/path",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_060),
            outcome: outcome,
            origin: .manual
        )
    }
}

private actor NotificationCenterSpy: TransferNotificationCenter {
    private(set) var requests: [TransferNotificationRequest] = []

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func add(_ request: TransferNotificationRequest) async throws {
        requests.append(request)
    }
}

private actor TransferNotifierSpy: TransferNotifying {
    private(set) var deliveredOutcomes: [TransferOutcome] = []

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async {
        deliveredOutcomes.append(record.outcome)
    }
}

private actor TransferHistorySpy: TransferHistoryPersisting {
    private let records: [TransferRecord]

    init(records: [TransferRecord] = []) {
        self.records = records
    }

    func load() async throws -> [TransferRecord] {
        records
    }

    func save(_ records: [TransferRecord]) async throws {}

    func quarantineCorruptFile() async {}
}
