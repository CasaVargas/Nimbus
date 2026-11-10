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

    /// Runs once, inside the next `startSync`, before it returns: the start
    /// request is in flight while it runs.
    func onNextStart(_ hook: @escaping @MainActor @Sendable () async -> Void) {
        lock.withLock { _onNextStart = hook }
    }
    private var _onNextStart: (@MainActor @Sendable () async -> Void)?

    func startSync(_ request: SyncRequest) async throws -> Int {
        if let hook = lock.withLock({ () -> (@MainActor @Sendable () async -> Void)? in
            defer { _onNextStart = nil }
            return _onNextStart
        }) {
            await hook()
        }
        return try lock.withLock {
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

    // MARK: Versions pruning

    struct Call: Hashable { let fs: String; let remote: String }
    private var _listings: [Call: [FileItem]] = [:]
    private var _listError: Error?
    private var _purgeError: Error?
    private var _listCalls: [Call] = []
    private var _purges: [Call] = []
    private var _onList: (@Sendable () async -> Void)?
    private var _onPurge: (@Sendable (Call) async -> Void)?

    var listCalls: [Call] { lock.withLock { _listCalls } }
    var purges: [Call] { lock.withLock { _purges } }

    func setListing(fs: String, remote: String, _ items: [FileItem]) {
        lock.withLock { _listings[Call(fs: fs, remote: remote)] = items }
    }
    func failLists(with error: Error?) { lock.withLock { _listError = error } }
    func failPurges(with error: Error?) { lock.withLock { _purgeError = error } }
    /// Runs inside each `listFiles` before it returns; a test can hold a listing open.
    func onList(_ hook: (@Sendable () async -> Void)?) { lock.withLock { _onList = hook } }

    func listFiles(fs: String, remote: String) async throws -> [FileItem] {
        let hook = lock.withLock { () -> (@Sendable () async -> Void)? in
            _listCalls.append(Call(fs: fs, remote: remote))
            return _onList
        }
        if let hook { await hook() }
        return try lock.withLock {
            if let error = _listError { throw error }
            return _listings[Call(fs: fs, remote: remote)] ?? []
        }
    }

    /// Runs inside each successful `purge`, after it is recorded and before
    /// it returns; a test can change the job between two purges.
    func onPurge(_ hook: (@Sendable (Call) async -> Void)?) { lock.withLock { _onPurge = hook } }

    func purge(fs: String, remote: String) async throws {
        let call = Call(fs: fs, remote: remote)
        let hook = try lock.withLock { () -> (@Sendable (Call) async -> Void)? in
            if let error = _purgeError { throw error }
            _purges.append(call)
            return _onPurge
        }
        if let hook { await hook(call) }
    }
}

extension BackupFixtures {
    /// A listing entry as `operations/list` returns it.
    static func listed(_ name: String, isDir: Bool = true, modTime: Date? = nil) -> FileItem {
        FileItem(path: name, name: name, size: isDir ? -1 : 10, mimeType: isDir ? "inode/directory" : "text/plain",
                 modTime: modTime, isDir: isDir, fileID: nil, qualifiedRemotePath: name)
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
