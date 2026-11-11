import Foundation

/// Files whose last upload to the cloud failed, per cloud. Compiled into
/// both the app and the File Provider extension, which share the file
/// through the app-group container: the extension records and clears
/// failures around its uploads and reads them to badge items in Finder; the
/// app drops a cloud's file when the cloud is removed.
///
/// Keys are File Provider item identifiers' raw values (`"<remote>:<path>"`).
/// One small JSON file per cloud, the same pattern as `PinStore`: writes are
/// coordinated and atomic, reads are cached against the file's modification
/// date. Being in the app group, failures survive a relaunch until a later
/// upload of the same item succeeds.
final class UploadFailureStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var cache: [String: (modified: Date?, failures: Set<String>)] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared app-group container, or nil when the group
    /// container isn't available (unsigned test builds).
    static let shared: UploadFailureStore? = AppGroup.containerURL
        .map { UploadFailureStore(directory: $0.appendingPathComponent("UploadFailures", isDirectory: true)) }

    // MARK: - Reading

    func failures(domain: String) -> Set<String> {
        let url = fileURL(domain: domain)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock()
        if let cached = cache[domain], cached.modified == modified, modified != nil {
            lock.unlock()
            return cached.failures
        }
        lock.unlock()
        let failures = Self.decode(try? Data(contentsOf: url))
        lock.lock()
        cache[domain] = (modified, failures)
        lock.unlock()
        return failures
    }

    func hasFailed(_ identifier: String, domain: String) -> Bool {
        failures(domain: domain).contains(identifier)
    }

    // MARK: - Writing

    /// Records a failed upload. Returns true when the item wasn't already
    /// recorded (its badge changes and the system should hear about it).
    @discardableResult
    func record(_ identifier: String, domain: String) throws -> Bool {
        try update(domain: domain) { $0.insert(identifier) }
    }

    /// Clears the given items after a successful upload. Returns true when
    /// anything was recorded.
    @discardableResult
    func clear(_ identifiers: [String], domain: String) throws -> Bool {
        try update(domain: domain) { $0.subtract(identifiers) }
    }

    /// A rename or move: the item and everything under it keep their records
    /// at the new path.
    func moved(from old: String, to new: String, domain: String) throws {
        guard old != new else { return }
        try update(domain: domain) { failures in
            let affected = failures.filter { $0 == old || $0.hasPrefix(old + "/") }
            guard !affected.isEmpty else { return }
            failures.subtract(affected)
            for id in affected { failures.insert(new + String(id.dropFirst(old.count))) }
        }
    }

    /// A delete: the item and everything under it no longer have a failure.
    func removed(_ identifier: String, domain: String) throws {
        try update(domain: domain) { failures in
            failures = failures.filter { $0 != identifier && !$0.hasPrefix(identifier + "/") }
        }
    }

    /// The cloud itself was removed from Nimbus.
    func removeAll(domain: String) {
        try? FileManager.default.removeItem(at: fileURL(domain: domain))
        lock.lock()
        cache[domain] = nil
        lock.unlock()
    }

    // MARK: - Storage

    /// Applies `change` under file coordination; returns whether the set
    /// changed (nothing is written when it didn't).
    private func update(domain: String, _ change: (inout Set<String>) -> Void) throws -> Bool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(domain: domain)
        var coordinationError: NSError?
        var writeError: Error?
        var changed = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            var failures = Self.decode(try? Data(contentsOf: url))
            let before = failures
            change(&failures)
            guard failures != before else { return }
            do {
                try JSONEncoder().encode(failures.sorted()).write(to: url, options: .atomic)
                changed = true
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        lock.lock()
        cache[domain] = nil
        lock.unlock()
        return changed
    }

    private func fileURL(domain: String) -> URL {
        // Cloud names can contain characters that aren't safe in a file name.
        let safe = domain.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? domain
        return directory.appendingPathComponent("\(safe).json")
    }

    private static func decode(_ data: Data?) -> Set<String> {
        guard let data, let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }
}
