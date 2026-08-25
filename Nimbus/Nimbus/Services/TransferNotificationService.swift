import Foundation
import UserNotifications
import os

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

struct TransferNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

protocol TransferNotificationCenter: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: TransferNotificationRequest) async throws
}

protocol TransferNotifying: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async
}

struct TransferNotificationService: TransferNotifying, Sendable {
    private let center: any TransferNotificationCenter
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "transfer-notifications")

    init(center: any TransferNotificationCenter = UserNotificationCenterAdapter()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization()
    }

    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async {
        guard shouldDeliver(record.outcome, mode: mode) else { return }

        do {
            try await center.add(request(for: record))
        } catch {
            logger.error("Unable to deliver transfer notification: \(error.localizedDescription)")
        }
    }

    private func shouldDeliver(_ outcome: TransferOutcome, mode: TransferNotificationMode) -> Bool {
        switch (mode, outcome) {
        case (.off, _), (_, .cancelled), (.failuresOnly, .completed):
            false
        case (.failuresOnly, .failed), (.allTransfers, .completed), (.allTransfers, .failed):
            true
        }
    }

    private func request(for record: TransferRecord) -> TransferNotificationRequest {
        let operation = record.operation.rawValue.capitalized
        let isFailure: Bool
        switch record.outcome {
        case .completed:
            isFailure = false
        case .failed:
            isFailure = true
        case .cancelled:
            isFailure = false
        }

        return TransferNotificationRequest(
            identifier: record.id.uuidString,
            title: isFailure ? "Transfer Failed" : "Transfer Complete",
            body: "\(operation) transfer \(isFailure ? "failed" : "completed")."
        )
    }
}

struct NoopTransferNotifier: TransferNotifying, Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .denied
    }

    func requestAuthorization() async throws -> Bool {
        false
    }

    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async {}
}

private final class UserNotificationCenterAdapter: @unchecked Sendable, TransferNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: TransferNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil))
    }
}
