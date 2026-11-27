import Foundation

/// What each cloud's service can do, as rclone reports it, shared between
/// the app (which asks rclone) and the File Provider extension (which
/// decides whether Finder offers **Copy Share Link** and whether a remote
/// with fixed top-level folders hides top-level delete/rename/add actions).
///
/// Stored as one small JSON file in the app-group container. Reads are
/// cached against the file's modification date, like `PinStore`.
final class CloudCapabilities: @unchecked Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var shareLinks: Bool
        var fixedTopLevel: Bool

        init(shareLinks: Bool, fixedTopLevel: Bool = false) {
            self.shareLinks = shareLinks
            self.fixedTopLevel = fixedTopLevel
        }

        enum CodingKeys: String, CodingKey {
            case shareLinks
            case fixedTopLevel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shareLinks = try container.decode(Bool.self, forKey: .shareLinks)
            fixedTopLevel = try container.decodeIfPresent(Bool.self, forKey: .fixedTopLevel) ?? false
        }
    }

    private let url: URL
    private let lock = NSLock()
    private var cache: (modified: Date?, entries: [String: Entry])?

    init(url: URL) {
        self.url = url
    }

    static let shared: CloudCapabilities? = AppGroup.containerURL
        .map { CloudCapabilities(url: $0.appendingPathComponent("capabilities.json")) }

    func entries() -> [String: Entry] {
        // A URL caches resource values until its run loop turns, which an
        // extension's tasks may never do, so the date would go stale.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let modified = (try? fresh.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock()
        if let cache, cache.modified == modified, modified != nil {
            lock.unlock()
            return cache.entries
        }
        lock.unlock()
        let entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        lock.lock()
        cache = (modified, entries)
        lock.unlock()
        return entries
    }

    func canShare(cloud: String) -> Bool {
        entries()[cloud]?.shareLinks ?? false
    }

    func hasFixedTopLevel(cloud: String) -> Bool {
        entries()[cloud]?.fixedTopLevel ?? false
    }

    /// Replaces everything: clouds that no longer exist drop out.
    func replace(with entries: [String: Entry]) throws {
        guard entries != self.entries() else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        lock.lock()
        cache = nil
        lock.unlock()
    }
}
