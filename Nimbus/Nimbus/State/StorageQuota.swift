import Foundation
import RcloneKit

/// What a remote reports about its own capacity, shaped for display. Many
/// backends (S3, SFTP, alias) report nothing usable; every field is optional
/// so the UI can drop the gauge instead of inventing numbers.
struct StorageQuota: Equatable, Sendable {
    let used: Int64?
    let total: Int64?

    init(used: Int64?, total: Int64?) {
        self.used = used
        self.total = total
    }

    init(about: AboutResponse) {
        self.init(used: about.used, total: about.total)
    }

    var free: Int64? {
        guard let used, let total else { return nil }
        return max(0, total - used)
    }

    /// Used ÷ total, clamped to 0…1. Nil whenever the gauge cannot be drawn.
    var fraction: Double? {
        guard let used, let total, total > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var isNearlyFull: Bool { (fraction ?? 0) >= 0.9 }

    var usedText: String? { used.map(Self.format) }
    var totalText: String? { total.map(Self.format) }
    var freeText: String? { free.map(Self.format) }

    private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
