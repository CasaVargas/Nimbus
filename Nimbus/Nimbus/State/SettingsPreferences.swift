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
