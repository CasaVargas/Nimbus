import Foundation

enum MountAccessDefault: String, Codable, CaseIterable {
    case readWrite
    case readOnly
}

enum TransferNotificationMode: String, Codable, CaseIterable {
    case failuresOnly
    case allTransfers
    case off
}

enum TransferHistoryRetention: String, Codable, CaseIterable {
    case sevenDays
    case thirtyDays
    case forever
    case untilQuit
}

/// Minutes of inactivity before the rclone engine stops. Raw value 0 = never.
enum IdleDisconnect: Int, Codable, CaseIterable {
    case never = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue * 60)
    }
}
