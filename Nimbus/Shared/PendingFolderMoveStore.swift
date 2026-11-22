import Foundation

/// Folder moves currently in progress, per cloud.
///
/// If the system cancels a long folder move and later retries `modifyItem` for
/// the same move, the destination already holds our partial move. Remembering
/// `from → requested` and its resolved destination across the interruption
/// lets the retry resume into that destination instead of treating it as a
/// collision and splitting files across two folders.
final class PendingFolderMoveStore: @unchecked Sendable {
    static let defaultMaxAge: TimeInterval = 7 * 24 * 3600

    private struct Entry: Codable, Equatable, Sendable {
        let from: String
        let requested: String
        let resolved: String
        let startedAt: Date
    }

    private let directory: URL
    private let lock = NSLock()
    private var cache: [String: (modified: Date?, entries: [Entry])] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared app-group container, or nil when the group
    /// container isn't available (unsigned test builds).
    static let shared: PendingFolderMoveStore? = AppGroup.containerURL
        .map { PendingFolderMoveStore(directory: $0.appendingPathComponent("PendingFolderMoves", isDirectory: true)) }

    // MARK: - Reading

    /// The resolved destination of an unfinished `from → requested` move begun less than `maxAge` ago.
    func pendingDestination(
        from: String,
        requested: String,
        domain: String,
        now: Date = Date(),
        maxAge: TimeInterval = defaultMaxAge
    ) -> String? {
        entries(domain: domain).first { entry in
            entry.from == from && entry.requested == requested && now.timeIntervalSince(entry.startedAt) < maxAge
        }?.resolved
    }

    private func entries(domain: String) -> [Entry] {
        let url = fileURL(domain: domain)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock()
        if let cached = cache[domain], cached.modified == modified, modified != nil {
            lock.unlock()
            return cached.entries
        }
        lock.unlock()
        let entries = Self.decode(try? Data(contentsOf: url))
        lock.lock()
        cache[domain] = (modified, entries)
        lock.unlock()
        return entries
    }

    // MARK: - Writing

    func begin(from: String, requested: String, resolved: String, domain: String, now: Date = Date()) throws {
        try update(domain: domain, now: now) { entries in
            // One source folder can't have two moves in flight.
            entries.removeAll { $0.from == from }
            entries.append(Entry(from: from, requested: requested, resolved: resolved, startedAt: now))
        }
    }

    func finish(from: String, requested: String, domain: String) throws {
        try update(domain: domain, now: Date()) { entries in
            entries.removeAll { $0.from == from }
        }
    }

    // MARK: - Storage

    private func update(domain: String, now: Date, _ change: (inout [Entry]) -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(domain: domain)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            var entries = Self.decode(try? Data(contentsOf: url))
            let before = entries
            entries.removeAll { now.timeIntervalSince($0.startedAt) >= Self.defaultMaxAge }
            change(&entries)
            guard entries != before else { return }
            do {
                try JSONEncoder().encode(entries).write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        lock.lock()
        cache[domain] = nil
        lock.unlock()
    }

    private func fileURL(domain: String) -> URL {
        // Cloud names can contain characters that aren't safe in a file name.
        let safe = domain.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? domain
        return directory.appendingPathComponent("\(safe).json")
    }

    private static func decode(_ data: Data?) -> [Entry] {
        guard let data, let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
