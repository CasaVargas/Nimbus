import Foundation
import RcloneKit

/// The rclone calls backups need. `RcloneClient` provides them; tests use a
/// scripted mock.
protocol BackupRcloneClient: Sendable {
    func startSync(_ request: SyncRequest) async throws -> Int
    func jobStatus(id: Int) async throws -> Job
    func getStats(group: String?) async throws -> StatsResponse
    func stopJob(id: Int) async throws
}

extension RcloneClient: BackupRcloneClient {}

/// Plain-language versions of the rclone errors a backup commonly hits.
enum BackupErrorText {
    static func friendly(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("directory not found") {
            return String(localized: "The source folder isn't available. Is the drive connected?")
        }
        if lower.contains("mustn't overlap") {
            return String(localized: "The versions folder is inside the destination. Choose a folder outside it.")
        }
        return raw
    }
}
