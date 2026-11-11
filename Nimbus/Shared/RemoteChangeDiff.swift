import Foundation

/// A lightweight, comparable snapshot of one directory listing entry: just
/// enough to detect additions, deletions and metadata changes without
/// pulling in the full `FileItem`/`FileProviderItem` types.
///
/// Lives in `Shared/` so the diff logic below compiles into the app (and its
/// tests) as well as the File Provider extension.
struct SyncedItemRecord: Codable, Equatable, Sendable {
    /// `NSFileProviderItemIdentifier.rawValue`: `"<remote>:<fullPath>"`.
    let identifier: String
    let name: String
    let isDir: Bool
    let size: Int64
    let modTime: TimeInterval?
    /// Keep Downloaded state (see `FileProviderItem.keepState`). A pin
    /// changes nothing on the server, so without this a pin or unpin would
    /// diff as "no change" and the system would never re-read the item's
    /// content policy. Optional so snapshots saved by older builds decode.
    var keepState: Int? = nil
}

/// Persisted baseline for one listed container (root or a subfolder).
struct ContainerSnapshot: Codable, Sendable {
    /// Goes up only when the diffed contents actually change.
    var version: Int
    var items: [SyncedItemRecord]
}

/// Pure diff between a container's persisted snapshot and a fresh listing.
enum RemoteChangeDiff {
    struct Result: Equatable, Sendable {
        /// New or changed entries, in listing order.
        var changed: [String]
        /// Entries in the snapshot that the listing no longer has.
        var deleted: [String]
        /// The subset of `deleted` that were folders: their own snapshots
        /// are stale and should be dropped.
        var deletedFolders: [String]

        var hasChanges: Bool { !changed.isEmpty || !deleted.isEmpty }
    }

    /// `old == nil` means the container was never listed: everything is new.
    static func diff(old: [SyncedItemRecord]?, new: [SyncedItemRecord]) -> Result {
        let oldByID = index(old ?? [])
        let newByID = index(new)

        var changed: [String] = []
        var seen = Set<String>()
        for record in new where seen.insert(record.identifier).inserted {
            if oldByID[record.identifier] != record { changed.append(record.identifier) }
        }

        var deleted: [String] = []
        var deletedFolders: [String] = []
        var seenOld = Set<String>()
        for record in old ?? [] where newByID[record.identifier] == nil && seenOld.insert(record.identifier).inserted {
            deleted.append(record.identifier)
            if record.isDir { deletedFolders.append(record.identifier) }
        }
        return Result(changed: changed, deleted: deleted, deletedFolders: deletedFolders)
    }

    /// Identifiers of the folders in a listing: the next level a scan may
    /// walk into (only those with a snapshot of their own are walked).
    static func folders(in records: [SyncedItemRecord]) -> [String] {
        var seen = Set<String>()
        return records.filter { $0.isDir && seen.insert($0.identifier).inserted }.map(\.identifier)
    }

    /// Last entry wins on a duplicate identifier: listings shouldn't repeat
    /// a path, but a crash on a malformed one would be worse than a guess.
    private static func index(_ records: [SyncedItemRecord]) -> [String: SyncedItemRecord] {
        Dictionary(records.map { ($0.identifier, $0) }, uniquingKeysWith: { _, last in last })
    }
}

/// The working set's sync anchor: the Keep Downloaded change-log sequence,
/// a per-cloud generation that goes up whenever a remote scan finds
/// changes, and a format number. Little-endian Int64s.
///
/// Format 1 (24 bytes) means the working set's item listing was full
/// (every known item, for Spotlight). Earlier builds listed nothing: their
/// anchors (16 bytes, or 8 with the pin sequence only) decode as format 0,
/// and the enumerator expires them once so the system re-lists.
enum WorkingSetAnchor {
    static let currentFormat = 1

    static func encode(pinSequence: Int, remoteGeneration: Int, format: Int = currentFormat) -> Data {
        var data = Data()
        for value in [pinSequence, remoteGeneration, format] {
            data.append(withUnsafeBytes(of: Int64(value).littleEndian) { Data($0) })
        }
        return data
    }

    static func decode(_ data: Data) -> (pinSequence: Int, remoteGeneration: Int, format: Int) {
        func int(at offset: Int) -> Int {
            let slice = data.subdata(in: offset..<(offset + 8))
            return Int(slice.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian)
        }
        switch data.count {
        case 24: return (int(at: 0), int(at: 8), int(at: 16))
        case 16: return (int(at: 0), int(at: 8), 0)
        case 8: return (int(at: 0), 0, 0)
        default: return (0, 0, 0)
        }
    }
}

/// Every item the system knows about, for the working set's item listing
/// (the system indexes those items in Spotlight).
///
/// Walks the persisted snapshots from the root, no network: a folder with a
/// snapshot was listed by the system, so its entries exist on disk. A
/// folder without one is listed (it's an entry of a known folder) but not
/// entered. Each identifier appears once, so a malformed snapshot can't loop.
enum WorkingSetListing {
    struct Entry: Equatable, Sendable {
        /// Identifier of the folder the entry was listed in.
        let parent: String
        let record: SyncedItemRecord
    }

    static func collect(root: String, snapshot: (String) -> [SyncedItemRecord]?) -> [Entry] {
        var entries: [Entry] = []
        var seen: Set<String> = [root]
        var queue = [root]
        var index = 0
        while index < queue.count {
            let container = queue[index]
            index += 1
            guard let records = snapshot(container) else { continue }
            for record in records where seen.insert(record.identifier).inserted {
                entries.append(Entry(parent: container, record: record))
                if record.isDir { queue.append(record.identifier) }
            }
        }
        return entries
    }
}

/// Folders the system listed for the first time since the working set
/// last reported. Their entries reach the system through the folder's own
/// listing, which Spotlight doesn't index, so the working set reports them
/// once more as changes. Stored as one identifier per line.
enum NewlyListedLog {
    static func line(for container: String) -> Data { Data((container + "\n").utf8) }

    /// Identifiers in first-seen order, blank lines and repeats dropped.
    static func parse(_ data: Data) -> [String] {
        var seen = Set<String>()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }
}

/// One container listed and diffed during a remote scan. `payload` carries
/// whatever the caller needs for reporting (the extension keeps the
/// `FileProviderItem`s for the changed entries there).
struct RemoteChangeVisit<Payload: Sendable>: Sendable {
    let container: String
    let listing: [SyncedItemRecord]
    let diff: RemoteChangeDiff.Result
    let payload: Payload
}

/// Walks every container the system already knows about, level by level
/// from the root, and collects each one's diff.
///
/// A container is known when it has a snapshot (`isKnown`): the system
/// listed it once. The next level is taken from each visit's *fresh*
/// listing, so a folder deleted on the server is never walked into and a
/// folder created and opened since the last scan is. A container whose
/// listing fails (`visit` returns nil) is skipped, along with everything
/// below it, for this pass only.
enum RemoteChangeWalk {
    static func run<Payload: Sendable>(
        root: String,
        isKnown: @escaping @Sendable (String) -> Bool,
        width: Int = 4,
        visit: @escaping @Sendable (String) async -> RemoteChangeVisit<Payload>?
    ) async -> [RemoteChangeVisit<Payload>] {
        guard isKnown(root) else { return [] }
        var results: [RemoteChangeVisit<Payload>] = []
        var visited: Set<String> = [root]
        var level = [root]
        let width = max(width, 1)

        while !level.isEmpty {
            var next: [String] = []
            for start in stride(from: 0, to: level.count, by: width) {
                let chunk = Array(level[start..<min(start + width, level.count)])
                let visits = await withTaskGroup(of: (Int, RemoteChangeVisit<Payload>?).self) { group in
                    for (offset, container) in chunk.enumerated() {
                        group.addTask { (offset, await visit(container)) }
                    }
                    var collected = [RemoteChangeVisit<Payload>?](repeating: nil, count: chunk.count)
                    for await (offset, result) in group { collected[offset] = result }
                    return collected
                }
                for case let visit? in visits {
                    results.append(visit)
                    for folder in RemoteChangeDiff.folders(in: visit.listing)
                    where isKnown(folder) && visited.insert(folder).inserted {
                        next.append(folder)
                    }
                }
            }
            level = next
        }
        return results
    }
}
