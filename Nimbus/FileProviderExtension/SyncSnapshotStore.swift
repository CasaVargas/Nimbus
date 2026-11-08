import CryptoKit
import FileProvider
import RcloneKit
import os

/// A lightweight, comparable snapshot of one directory listing's item set —
/// just enough to detect additions, deletions, and metadata changes without
/// pulling in the full `FileItem`/`FileProviderItem` types.
struct SyncedItemRecord: Codable, Equatable, Sendable {
    /// `NSFileProviderItemIdentifier.rawValue` (full path form, see
    /// `Item.swift`'s identifier contract).
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

/// Persisted baseline for one enumerated container (root or a subfolder).
struct ContainerSnapshot: Codable, Sendable {
    /// Monotonically increasing only when the diffed contents actually
    /// change — this is what backs the sync anchor, so an anchor stays
    /// stable across no-op `enumerateChanges` calls.
    var version: Int
    var items: [SyncedItemRecord]
}

/// Result of diffing a fresh listing against the persisted baseline for a
/// container.
struct SnapshotDiff {
    let updated: [FileProviderItem]
    let deletedIdentifiers: [NSFileProviderItemIdentifier]
    var hasChanges: Bool { !updated.isEmpty || !deletedIdentifiers.isEmpty }
}

/// Persists per-container directory-listing snapshots in the app group
/// container so `FileProviderEnumerator.enumerateChanges` can do a real
/// diff (new/changed → `didUpdate`, vanished → `didDeleteItems`) instead of
/// re-announcing every item on every call. State must survive the
/// extension being relaunched (rule 4: stateless between launches), so this
/// is backed by a small JSON file per container rather than in-memory
/// state on the `FileProviderEnumerator` instance, which the system may
/// recreate at any time.
///
/// Not an actor: each container's state lives at its own file path (keyed
/// by a hash of the container identifier), so different containers never
/// contend. Concurrent `enumerateChanges` calls for the *same* container are
/// theoretically possible but not something the system does in practice;
/// writes use `.atomic` so a race can at worst lose one snapshot update
/// (causing a redundant `didUpdate` batch on the next call), never corrupt
/// the file.
enum SyncSnapshotStore {
    private static let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "sync-snapshot")

    /// Builds the comparable record set for a fresh listing, alongside the
    /// `FileProviderItem`s Finder needs for `didUpdate`.
    static func buildRecords(
        from files: [FileItem],
        parentIdentifier: NSFileProviderItemIdentifier,
        remoteName: String
    ) -> [(item: FileProviderItem, record: SyncedItemRecord)] {
        files.map { file in
            let item = FileProviderItem(from: file, parentIdentifier: parentIdentifier, remoteName: remoteName)
            let record = SyncedItemRecord(
                identifier: item.itemIdentifier.rawValue,
                name: file.name,
                isDir: file.isDir,
                size: file.size,
                modTime: file.modTime?.timeIntervalSince1970,
                keepState: item.keepState
            )
            return (item, record)
        }
    }

    /// Diffs a fresh listing against the persisted baseline for
    /// `containerIdentifier` and, if anything changed, persists the new
    /// baseline (bumping `version`). Returns the diff and the anchor that
    /// should be reported for this call.
    static func diffAndPersist(
        remoteName: String,
        containerIdentifier: NSFileProviderItemIdentifier,
        current: [(item: FileProviderItem, record: SyncedItemRecord)]
    ) -> (diff: SnapshotDiff, anchor: NSFileProviderSyncAnchor) {
        let old = load(remoteName: remoteName, containerIdentifier: containerIdentifier)
        let oldByID = Dictionary(uniqueKeysWithValues: (old?.items ?? []).map { ($0.identifier, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: current.map { ($0.record.identifier, $0.record) })

        var updated: [FileProviderItem] = []
        for (item, record) in current {
            if let oldRecord = oldByID[record.identifier] {
                if oldRecord != record { updated.append(item) }
            } else {
                updated.append(item)
            }
        }

        let deletedIdentifiers = (old?.items ?? [])
            .filter { newByID[$0.identifier] == nil }
            .map { NSFileProviderItemIdentifier($0.identifier) }

        let diff = SnapshotDiff(updated: updated, deletedIdentifiers: deletedIdentifiers)
        let newVersion = diff.hasChanges ? (old?.version ?? 0) + 1 : (old?.version ?? 0)

        if diff.hasChanges || old == nil {
            let snapshot = ContainerSnapshot(version: newVersion, items: current.map(\.record))
            save(snapshot, remoteName: remoteName, containerIdentifier: containerIdentifier)
        }

        return (diff, anchor(forVersion: newVersion))
    }

    /// Persists the baseline for a full `enumerateItems` listing without
    /// diffing (there's nothing to diff against on a fresh full pass — this
    /// just seeds the baseline the next `enumerateChanges` call will diff
    /// against).
    static func seed(
        remoteName: String,
        containerIdentifier: NSFileProviderItemIdentifier,
        current: [(item: FileProviderItem, record: SyncedItemRecord)]
    ) {
        let old = load(remoteName: remoteName, containerIdentifier: containerIdentifier)
        let snapshot = ContainerSnapshot(version: old?.version ?? 0, items: current.map(\.record))
        save(snapshot, remoteName: remoteName, containerIdentifier: containerIdentifier)
    }

    static func currentAnchor(remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) -> NSFileProviderSyncAnchor {
        anchor(forVersion: load(remoteName: remoteName, containerIdentifier: containerIdentifier)?.version ?? 0)
    }

    // MARK: - Anchor encoding

    private static func anchor(forVersion version: Int) -> NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(withUnsafeBytes(of: version) { Data($0) })
    }

    // MARK: - Storage

    private static func load(remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) -> ContainerSnapshot? {
        guard let url = fileURL(remoteName: remoteName, containerIdentifier: containerIdentifier) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ContainerSnapshot.self, from: data)
    }

    private static func save(_ snapshot: ContainerSnapshot, remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) {
        guard let url = fileURL(remoteName: remoteName, containerIdentifier: containerIdentifier) else {
            logger.warning("No writable location for sync snapshot state — change tracking degrades to full-refresh")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to persist sync snapshot: \(String(describing: error))")
        }
    }

    /// `<appGroupContainer>/FileProviderSync/<remoteName>/<sha256(containerIdentifier)>.json`.
    /// The identifier is hashed rather than used verbatim as a path
    /// component since it can contain `/` and `:` and, for deeply nested
    /// folders, exceed filename length limits.
    private static func fileURL(remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) -> URL? {
        guard let containerURL = FileProviderRetry.appGroupContainerURL() else { return nil }
        let digest = SHA256.hash(data: Data(containerIdentifier.rawValue.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        return containerURL
            .appendingPathComponent("FileProviderSync", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
}
