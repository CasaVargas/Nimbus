import CryptoKit
import FileProvider
import RcloneKit
import os

// `SyncedItemRecord`, `ContainerSnapshot` and the pure diff live in
// `Shared/RemoteChangeDiff.swift` (unit-tested from the app target).

/// Result of diffing a fresh listing against the persisted baseline for a
/// container.
struct SnapshotDiff {
    let updated: [FileProviderItem]
    let deletedIdentifiers: [NSFileProviderItemIdentifier]
    /// Deleted entries that were folders (their snapshots are stale).
    var deletedFolders: [NSFileProviderItemIdentifier] = []
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
        let result = RemoteChangeDiff.diff(old: old?.items, new: current.map(\.record))
        let changed = Set(result.changed)
        var emitted = Set<String>()
        let updated = current
            .filter { changed.contains($0.record.identifier) && emitted.insert($0.record.identifier).inserted }
            .map(\.item)

        let diff = SnapshotDiff(
            updated: updated,
            deletedIdentifiers: result.deleted.map { NSFileProviderItemIdentifier($0) },
            deletedFolders: result.deletedFolders.map { NSFileProviderItemIdentifier($0) }
        )
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

    /// Whether the system has listed this container at least once (a
    /// remote scan only walks containers it knows about).
    static func hasSnapshot(remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) -> Bool {
        guard let url = fileURL(remoteName: remoteName, containerIdentifier: containerIdentifier) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Drops a container's snapshot (the folder was deleted on the server).
    static func removeSnapshot(remoteName: String, containerIdentifier: NSFileProviderItemIdentifier) {
        guard let url = fileURL(remoteName: remoteName, containerIdentifier: containerIdentifier) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// rclone path of a container: `""` for the root, otherwise the
    /// identifier without its `"<remote>:"` prefix.
    static func remotePath(of containerIdentifier: NSFileProviderItemIdentifier, remoteName: String) -> String {
        if containerIdentifier == .rootContainer { return "" }
        let raw = containerIdentifier.rawValue
        let prefix = "\(remoteName):"
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }

    // MARK: - Remote generation (working-set anchor)

    /// Goes up whenever a remote scan finds changes; half of the working
    /// set's sync anchor (see `WorkingSetAnchor`).
    static func remoteGeneration(remoteName: String) -> Int {
        guard let url = generationURL(remoteName: remoteName),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    @discardableResult
    static func bumpRemoteGeneration(remoteName: String) -> Int {
        let next = remoteGeneration(remoteName: remoteName) + 1
        guard let url = generationURL(remoteName: remoteName) else { return next }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try String(next).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Failed to persist remote generation: \(String(describing: error))")
        }
        return next
    }

    private static func generationURL(remoteName: String) -> URL? {
        FileProviderRetry.appGroupContainerURL()?
            .appendingPathComponent("FileProviderSync", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
            .appendingPathComponent("remote-generation", isDirectory: false)
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
