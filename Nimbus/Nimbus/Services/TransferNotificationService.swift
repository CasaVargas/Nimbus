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
    /// Set for backup notifications, so a click can open that backup.
    var backupID: UUID? = nil

    static let backupIDKey = "backupID"

    var userInfo: [String: String] {
        backupID.map { [Self.backupIDKey: $0.uuidString] } ?? [:]
    }

    static func backupID(fromUserInfo userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[backupIDKey] as? String).flatMap(UUID.init(uuidString:))
    }
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
            let status = await center.authorizationStatus()
            switch status {
            case .authorized:
                break
            case .denied:
                return
            case .notDetermined:
                guard try await center.requestAuthorization() else { return }
            }
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
        if record.origin == .backup, let backupID = record.backupID {
            return backupRequest(for: record, backupID: backupID)
        }
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

extension TransferNotificationService {
    private func backupRequest(for record: TransferRecord, backupID: UUID) -> TransferNotificationRequest {
        let name = record.title ?? ""
        let title: String
        let body: String
        switch record.summary?.outcome {
        case .limitHit:
            title = String(localized: "Backup \(name) stopped")
            if let limit = record.summary?.removalLimit {
                body = String(localized: "It would have removed more than \(BackupStatus.fileCount(limit)). Open Nimbus to preview it.")
            } else {
                body = String(localized: "It would have removed more files than the limit allows. Open Nimbus to preview it.")
            }
        default:
            if case .failed(let jobError) = record.outcome {
                title = String(localized: "Backup \(name) failed")
                // The summary carries the real reason (e.g. the stats' last
                // error for delete failures); the job error is rclone's raw one.
                var message = jobError
                if case .failed(let reason)? = record.summary?.outcome { message = reason }
                message = BackupErrorText.friendly(message)
                body = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
            } else {
                title = String(localized: "Backed up \(name)")
                body = Self.backupBody(copied: record.summary?.copied ?? 0,
                                       replaced: record.summary?.replaced ?? 0,
                                       removed: record.summary?.removed ?? 0,
                                       versions: record.summary?.movesToVersions ?? false)
            }
        }
        return TransferNotificationRequest(identifier: record.id.uuidString, title: title, body: body, backupID: backupID)
    }

    /// "13 files backed up, 2 moved to versions." Replaced files count as
    /// backed up. Removals are moves into versions only for a mirror with
    /// versions; otherwise they are real deletes. A run that only removed
    /// says just that: "40 moved to versions." or "40 removed."
    static func backupBody(copied: Int, replaced: Int, removed: Int, versions: Bool) -> String {
        let backedUpCount = copied + replaced
        let gone = versions ? replaced + removed : removed
        if backedUpCount == 0, gone == 0 { return String(localized: "No changes.") }
        var parts: [String] = []
        if backedUpCount > 0 {
            parts.append(backedUpCount == 1
                ? String(localized: "1 file backed up")
                : String(localized: "\(backedUpCount) files backed up"))
        }
        if gone > 0 {
            parts.append(versions ? String(localized: "\(gone) moved to versions") : String(localized: "\(gone) removed"))
        }
        return parts.joined(separator: ", ") + "."
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
        content.userInfo = request.userInfo

        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil))
    }
}
