import Foundation
import Testing
@testable import Nimbus

@Suite("TransferNotificationService")
struct TransferNotificationServiceTests {
    @Test(arguments: [
        NotificationAuthorizationStatus.notDetermined,
        .denied,
        .authorized
    ])
    func authorizationStatusReflectsCenterStatus(_ status: NotificationAuthorizationStatus) async {
        let center = NotificationCenterSpy(authorizationStatus: status)
        let service = TransferNotificationService(center: center)

        #expect(await service.authorizationStatus() == status)
    }

    @Test func failuresOnlySuppressesSuccessWithoutPrompting() async {
        let center = NotificationCenterSpy(authorizationStatus: .notDetermined)
        let service = TransferNotificationService(center: center)

        await service.deliver(completedRecord, mode: .failuresOnly)

        #expect(await center.requests.isEmpty)
        #expect(await center.authorizationStatusCallCount == 0)
        #expect(await center.requestAuthorizationCallCount == 0)
    }

    @Test func failuresOnlyDeliversFailureWhenAuthorized() async {
        let center = NotificationCenterSpy(authorizationStatus: .authorized)
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        let requests = await center.requests
        #expect(requests.count == 1)
        #expect(requests.first?.body == "Copy transfer failed.")
        #expect(!requests.contains { $0.body.contains("source:private/path") })
        #expect(!requests.contains { $0.body.contains("destination:private/path") })
    }

    @Test func qualifyingDeliveryRequestsAuthorizationWhenUndetermined() async {
        let center = NotificationCenterSpy(
            authorizationStatus: .notDetermined,
            requestAuthorizationResult: .success(true)
        )
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        #expect(await center.authorizationStatusCallCount == 1)
        #expect(await center.requestAuthorizationCallCount == 1)
        #expect(await center.requests.count == 1)
    }

    @Test func deniedAuthorizationSkipsDelivery() async {
        let center = NotificationCenterSpy(authorizationStatus: .denied)
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        #expect(await center.authorizationStatusCallCount == 1)
        #expect(await center.requestAuthorizationCallCount == 0)
        #expect(await center.requests.isEmpty)
    }

    @Test func deniedRequestResultSkipsDelivery() async {
        let center = NotificationCenterSpy(
            authorizationStatus: .notDetermined,
            requestAuthorizationResult: .success(false)
        )
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        #expect(await center.authorizationStatusCallCount == 1)
        #expect(await center.requestAuthorizationCallCount == 1)
        #expect(await center.requests.isEmpty)
    }

    @Test func authorizationRequestErrorSkipsDelivery() async {
        let center = NotificationCenterSpy(
            authorizationStatus: .notDetermined,
            requestAuthorizationResult: .failure(NotificationCenterSpyError.requestFailed)
        )
        let service = TransferNotificationService(center: center)

        await service.deliver(failedRecord, mode: .failuresOnly)

        #expect(await center.authorizationStatusCallCount == 1)
        #expect(await center.requestAuthorizationCallCount == 1)
        #expect(await center.requests.isEmpty)
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

    // MARK: Backups

    @Test func backupSuccessCopy() async {
        let center = NotificationCenterSpy(authorizationStatus: .authorized)
        let service = TransferNotificationService(center: center)

        await service.deliver(backupRecord(.completed, copied: 12, replaced: 1, removed: 1, versions: true),
                              mode: .allTransfers)

        let request = await center.requests.first
        #expect(request?.title == "Backed up Documents to B2")
        #expect(request?.body == "13 files backed up, 2 moved to versions.")
        #expect(request?.backupID == Self.backupID)
    }

    @Test func backupSuccessBodyHandlesOneAndNone() async {
        #expect(TransferNotificationService.backupBody(copied: 1, replaced: 0, removed: 0, versions: false) == "1 file backed up.")
        #expect(TransferNotificationService.backupBody(copied: 0, replaced: 0, removed: 0, versions: false) == "No changes.")
        #expect(TransferNotificationService.backupBody(copied: 0, replaced: 0, removed: 0, versions: true) == "No changes.")
    }

    @Test func removalOnlyRunWithVersionsSaysMovedToVersions() {
        #expect(TransferNotificationService.backupBody(copied: 0, replaced: 0, removed: 40, versions: true)
            == "0 files backed up, 40 moved to versions.")
    }

    @Test func removalOnlyRunWithoutVersionsSaysRemoved() {
        #expect(TransferNotificationService.backupBody(copied: 0, replaced: 0, removed: 40, versions: false)
            == "0 files backed up, 40 removed.")
    }

    @Test func copiedAndRemovedWithoutVersions() {
        #expect(TransferNotificationService.backupBody(copied: 5, replaced: 0, removed: 2, versions: false)
            == "5 files backed up, 2 removed.")
    }

    @Test func backupFailureUsesTheFriendlySummaryReason() async {
        let center = NotificationCenterSpy(authorizationStatus: .authorized)
        let service = TransferNotificationService(center: center)

        await service.deliver(
            backupRecord(.failed("failed to delete 3 files"), summary: .failed("Access denied\nmore"), copied: 0),
            mode: .failuresOnly)
        await service.deliver(
            backupRecord(.failed("directory not found"), summary: .failed("directory not found"), copied: 0),
            mode: .failuresOnly)

        let bodies = await center.requests.map(\.body)
        #expect(bodies == ["Access denied", "The source folder isn't available. Is the drive connected?"])
    }

    @Test func backupFailureCopy() async {
        let center = NotificationCenterSpy(authorizationStatus: .authorized)
        let service = TransferNotificationService(center: center)

        await service.deliver(backupRecord(.failed("Network unavailable\nsecond line")), mode: .failuresOnly)

        let request = await center.requests.first
        #expect(request?.title == "Backup Documents to B2 failed")
        #expect(request?.body == "Network unavailable")
        #expect(request?.backupID == Self.backupID)
    }

    @Test func backupLimitHitNotifiesUnderFailuresOnly() async {
        let center = NotificationCenterSpy(authorizationStatus: .authorized)
        let service = TransferNotificationService(center: center)

        await service.deliver(backupRecord(.failed("failed to delete 100 files"), summary: .limitHit, limit: 100),
                              mode: .failuresOnly)

        let request = await center.requests.first
        #expect(request?.title == "Backup Documents to B2 stopped")
        #expect(request?.body == "It would have removed more than 100 files. Open Nimbus to preview it.")
        #expect(request?.backupID == Self.backupID)
    }

    @Test func backupSuccessSilentUnderFailuresOnly() async {
        let center = NotificationCenterSpy(authorizationStatus: .notDetermined)
        let service = TransferNotificationService(center: center)

        await service.deliver(backupRecord(.completed), mode: .failuresOnly)

        #expect(await center.requests.isEmpty)
        #expect(await center.requestAuthorizationCallCount == 0)
    }

    @Test func backupIDRoundTripsThroughUserInfo() {
        let request = TransferNotificationRequest(identifier: "x", title: "t", body: "b", backupID: Self.backupID)
        #expect(TransferNotificationRequest.backupID(fromUserInfo: request.userInfo) == Self.backupID)
        #expect(TransferNotificationRequest.backupID(fromUserInfo: [:]) == nil)
        #expect(TransferNotificationRequest(identifier: "x", title: "t", body: "b").userInfo.isEmpty)
    }

    private static let backupID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    private func backupRecord(
        _ outcome: TransferOutcome,
        summary: BackupRunSummary.Outcome? = nil,
        copied: Int = 3,
        replaced: Int = 0,
        removed: Int = 1,
        versions: Bool = false,
        limit: Int? = nil
    ) -> TransferRecord {
        var record = record(outcome: outcome, origin: .backup)
        record.backupID = Self.backupID
        record.title = "Documents to B2"
        var run = BackupRunSummary(
            startedAt: record.startedAt, finishedAt: record.completedAt, trigger: .scheduled,
            outcome: summary ?? { if case .failed(let m) = outcome { .failed(m) } else { .completed } }(),
            copied: copied, replaced: replaced, removed: removed, errors: 0, bytes: 10
        )
        run.movesToVersions = versions
        run.removalLimit = limit
        record.summary = run
        return record
    }

    private var completedRecord: TransferRecord {
        record(outcome: .completed)
    }

    private var failedRecord: TransferRecord {
        record(outcome: .failed("Network unavailable"))
    }

    private func record(outcome: TransferOutcome, origin: TransferOrigin = .manual) -> TransferRecord {
        TransferRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            jobID: 7,
            operation: .copy,
            source: "source:private/path",
            destination: "destination:private/path",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_060),
            outcome: outcome,
            origin: origin
        )
    }
}

private actor NotificationCenterSpy: TransferNotificationCenter {
    private let authorizationStatusValue: NotificationAuthorizationStatus
    private let requestAuthorizationResult: Result<Bool, Error>
    private let addResult: Result<Void, Error>
    private(set) var authorizationStatusCallCount = 0
    private(set) var requestAuthorizationCallCount = 0
    private(set) var requests: [TransferNotificationRequest] = []

    init(
        authorizationStatus: NotificationAuthorizationStatus = .authorized,
        requestAuthorizationResult: Result<Bool, Error> = .success(true),
        addResult: Result<Void, Error> = .success(())
    ) {
        self.authorizationStatusValue = authorizationStatus
        self.requestAuthorizationResult = requestAuthorizationResult
        self.addResult = addResult
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        authorizationStatusCallCount += 1
        return authorizationStatusValue
    }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        return try requestAuthorizationResult.get()
    }

    func add(_ request: TransferNotificationRequest) async throws {
        try addResult.get()
        requests.append(request)
    }
}

private enum NotificationCenterSpyError: Error {
    case requestFailed
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
