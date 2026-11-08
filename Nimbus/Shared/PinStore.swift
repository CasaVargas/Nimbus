import Foundation

/// Items the user chose to **Keep Downloaded**, per cloud. Compiled into
/// both the app and the File Provider extension, which share the file
/// through the app-group container: the extension reads it to set each
/// item's content policy, and both sides write it (Finder's action, the
/// inspector's switch).
///
/// Keys are File Provider item identifiers' raw values: `"<remote>:<path>"`,
/// or `NSFileProviderItemIdentifier.rootContainer.rawValue` for a cloud's
/// top folder. One small JSON file per cloud; writes are coordinated and
/// atomic, and reads are cached against the file's modification date so
/// enumerating thousands of items doesn't re-read the file each time.
final class PinStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var cache: [String: (modified: Date?, pins: Set<String>)] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared app-group container, or nil when the group
    /// container isn't available (unsigned test builds).
    static let shared: PinStore? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.app.casavargas.nimbus")
        .map { PinStore(directory: $0.appendingPathComponent("Pins", isDirectory: true)) }

    // MARK: - Reading

    func pins(domain: String) -> Set<String> {
        let url = fileURL(domain: domain)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock()
        if let cached = cache[domain], cached.modified == modified, modified != nil {
            lock.unlock()
            return cached.pins
        }
        lock.unlock()
        let pins = Self.decode(try? Data(contentsOf: url))
        lock.lock()
        cache[domain] = (modified, pins)
        lock.unlock()
        return pins
    }

    func isPinned(_ identifier: String, domain: String) -> Bool {
        pins(domain: domain).contains(identifier)
    }

    // MARK: - Writing

    func setPinned(_ pinned: Bool, identifiers: [String], domain: String) throws {
        try update(domain: domain) { pins in
            if pinned { pins.formUnion(identifiers) } else { pins.subtract(identifiers) }
        }
    }

    /// Records `identifiers` in the change log even when their pin state is
    /// unchanged, so the system re-reads them. Used by Finder's actions and
    /// the inspector switch: if the system's view ever drifted from this
    /// store, repeating the action repairs it.
    func markChanged(_ identifiers: [String], domain: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: changeLogURL(domain: domain), options: .forMerging,
                                       error: &coordinationError) { _ in
            do { try appendChanges(identifiers, domain: domain) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// A rename or move: the item and everything under it keep their pins at
    /// the new path.
    func moved(from old: String, to new: String, domain: String) throws {
        guard old != new else { return }
        try update(domain: domain) { pins in
            let affected = pins.filter { $0 == old || $0.hasPrefix(old + "/") }
            guard !affected.isEmpty else { return }
            pins.subtract(affected)
            for id in affected { pins.insert(new + String(id.dropFirst(old.count))) }
        }
    }

    /// A delete: the item and everything under it are no longer pinned.
    func removed(_ identifier: String, domain: String) throws {
        try update(domain: domain) { pins in
            pins = pins.filter { $0 != identifier && !$0.hasPrefix(identifier + "/") }
        }
    }

    /// The cloud itself was removed from Nimbus.
    func removeAll(domain: String) {
        try? FileManager.default.removeItem(at: fileURL(domain: domain))
        try? FileManager.default.removeItem(at: changeLogURL(domain: domain))
        lock.lock()
        cache[domain] = nil
        lock.unlock()
    }

    // MARK: - Storage

    private func update(domain: String, _ change: (inout Set<String>) -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(domain: domain)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            var pins = Self.decode(try? Data(contentsOf: url))
            let before = pins
            change(&pins)
            guard pins != before else { return }
            do {
                try Self.encode(pins).write(to: url, options: .atomic)
                try appendChanges(Array(pins.symmetricDifference(before)), domain: domain)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        lock.lock()
        cache[domain] = nil
        lock.unlock()
    }

    // MARK: - Change log

    /// Pins change nothing on the server, so the File Provider extension
    /// can't discover them by listing. The replicated model only accepts
    /// signals for the working set, so every pin change is appended here and
    /// the working-set enumerator reports exactly these items as updated.
    /// `sequence` doubles as that enumerator's sync anchor.
    struct ChangeLog: Codable, Equatable {
        struct Entry: Codable, Equatable { let sequence: Int; let identifier: String }
        var sequence: Int = 0
        var entries: [Entry] = []
    }

    static let changeLogLimit = 500

    /// Identifiers changed after `sequence`, and the latest sequence. nil
    /// when `sequence` is older than the retained log (the enumerator then
    /// reports the anchor as expired and the system re-enumerates).
    func changes(domain: String, after sequence: Int) -> (identifiers: [String], latest: Int)? {
        let log = changeLog(domain: domain)
        if let oldest = log.entries.first?.sequence, sequence < oldest - 1 { return nil }
        if sequence > log.sequence { return nil }
        let ids = log.entries.filter { $0.sequence > sequence }.map(\.identifier)
        var seen = Set<String>()
        return (ids.filter { seen.insert($0).inserted }, log.sequence)
    }

    func latestSequence(domain: String) -> Int { changeLog(domain: domain).sequence }

    private func changeLog(domain: String) -> ChangeLog {
        guard let data = try? Data(contentsOf: changeLogURL(domain: domain)),
              let log = try? JSONDecoder().decode(ChangeLog.self, from: data) else { return ChangeLog() }
        return log
    }

    private func appendChanges(_ identifiers: [String], domain: String) throws {
        guard !identifiers.isEmpty else { return }
        var log = changeLog(domain: domain)
        for id in identifiers.sorted() {
            log.sequence += 1
            log.entries.append(.init(sequence: log.sequence, identifier: id))
        }
        if log.entries.count > Self.changeLogLimit {
            log.entries.removeFirst(log.entries.count - Self.changeLogLimit)
        }
        try JSONEncoder().encode(log).write(to: changeLogURL(domain: domain), options: .atomic)
    }

    private func changeLogURL(domain: String) -> URL {
        let safe = domain.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? domain
        return directory.appendingPathComponent("\(safe).changes.json")
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

    private static func encode(_ pins: Set<String>) throws -> Data {
        try JSONEncoder().encode(pins.sorted())
    }
}

/// How a pin turns into File Provider behaviour, kept apart from FileProvider
/// types so it can be unit-tested in the app's test target.
enum PinPolicy: Equatable {
    /// Download when opened; macOS may remove the download (the root's policy).
    case downloadLazily
    /// Download now, keep current, never remove the download.
    case keepDownloaded
    /// Whatever the parent folder does.
    case inherited

    /// `NSFileProviderItemIdentifier.rootContainer.rawValue`, spelled out so
    /// this file needn't import FileProvider (a test checks they match).
    static let rootKey = "NSFileProviderRootContainerItemIdentifier"

    static func policy(isRoot: Bool, isPinned: Bool) -> PinPolicy {
        if isPinned { return .keepDownloaded }
        return isRoot ? .downloadLazily : .inherited
    }

    /// True when a folder above `identifier` is pinned, so the item is kept
    /// downloaded by inheritance even though it isn't pinned itself.
    /// `rootKey` is the root container identifier's raw value.
    static func keptByAncestor(_ identifier: String, pins: Set<String>, rootKey: String) -> Bool {
        guard identifier != rootKey else { return false }
        if pins.contains(rootKey) { return true }
        return pins.contains { identifier.hasPrefix($0 + "/") }
    }

    /// The parent's identifier for `"<remote>:<path>"`, or nil when the
    /// parent is the cloud's root container.
    static func parentIdentifier(of identifier: String) -> String? {
        guard let colon = identifier.firstIndex(of: ":") else { return nil }
        let path = identifier[identifier.index(after: colon)...]
        guard let slash = path.lastIndex(of: "/") else { return nil }
        return String(identifier[..<colon]) + ":" + path[..<slash]
    }
}
