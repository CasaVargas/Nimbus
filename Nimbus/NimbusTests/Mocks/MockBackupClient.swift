import Foundation
@testable import Nimbus
@testable import RcloneKit

/// Scriptable rclone client for previews and backup runs. Each `startSync`
/// gets the next job id (100, 101, …). `jobStatus` returns the scripted
/// statuses for that id in order, repeating the last one.
final class MockBackupClient: BackupRcloneClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [SyncRequest] = []
    private var _stopped: [Int] = []
    private var _statuses: [Int: [Job]] = [:]
    private var _stats: [String: StatsResponse] = [:]
    private var _nextID = 100
    private var _startError: Error?
    /// Runs before each `jobStatus` returns; tests use it to observe state.
    var onJobStatus: (@Sendable (Int) async -> Void)?

    var requests: [SyncRequest] { lock.withLock { _requests } }
    var stopped: [Int] { lock.withLock { _stopped } }

    func script(jobID: Int, _ statuses: [Job]) { lock.withLock { _statuses[jobID] = statuses } }
    func setStats(group: String, _ stats: StatsResponse) { lock.withLock { _stats[group] = stats } }
    func failStarts(with error: Error?) { lock.withLock { _startError = error } }

    func startSync(_ request: SyncRequest) async throws -> Int {
        try lock.withLock {
            if let error = _startError { throw error }
            _requests.append(request)
            defer { _nextID += 1 }
            return _nextID
        }
    }

    func jobStatus(id: Int) async throws -> Job {
        if let onJobStatus { await onJobStatus(id) }
        return lock.withLock {
            var queue = _statuses[id] ?? [BackupFixtures.job(id: id, finished: false)]
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            _statuses[id] = queue
            return next
        }
    }

    func getStats(group: String?) async throws -> StatsResponse {
        lock.withLock { _stats[group ?? ""] } ?? BackupFixtures.stats(transfers: 0, deletes: 0, renames: 0)
    }

    func stopJob(id: Int) async throws {
        lock.withLock { _stopped.append(id) }
    }
}

/// Transfer history that never touches disk.
actor InMemoryTransferHistory: TransferHistoryPersisting {
    private(set) var saved: [[TransferRecord]] = []
    func load() async throws -> [TransferRecord] { [] }
    func save(_ records: [TransferRecord]) async throws { saved.append(records) }
    func quarantineCorruptFile() async {}
}

extension BackupFixtures {
    static func job(
        id: Int,
        finished: Bool,
        success: Bool = false,
        error: String = "",
        output: String? = nil
    ) -> Job {
        let outputField = output.map { #""output": \#($0),"# } ?? ""
        let json = """
        {"id": \(id), "group": "job/\(id)", "startTime": "", "endTime": "", "error": "\(error)",
         \(outputField) "finished": \(finished), "success": \(success), "duration": 1}
        """
        return try! JSONDecoder().decode(Job.self, from: Data(json.utf8))
    }

    static func listedStats(_ listed: Int) -> StatsResponse {
        let json = """
        {"speed": 0, "bytes": 0, "errors": 0, "checks": 0, "transfers": 0, "deletes": 0,
         "listed": \(listed), "elapsedTime": 1, "totalBytes": 0, "totalTransfers": 0, "totalChecks": 0}
        """
        return try! JSONDecoder().decode(StatsResponse.self, from: Data(json.utf8))
    }
}
