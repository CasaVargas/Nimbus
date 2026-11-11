import FileProvider
import RcloneKit
import os

/// Finds what changed on the server in every folder the system already
/// knows about, for the working-set enumerator to report. A replicated
/// extension gets no other chance: the system never asks a folder's own
/// enumerator for changes after its first listing.
///
/// See `RemoteChangeWalk` (Shared) for the walk itself; this type supplies
/// the rclone listing, the snapshot store and the `FileProviderItem`s.
enum RemoteChangeScanner {
    struct Outcome: Sendable {
        var updated: [FileProviderItem] = []
        var deleted: [NSFileProviderItemIdentifier] = []
        var listedContainers = 0
        var hasChanges: Bool { !updated.isEmpty || !deleted.isEmpty }
    }

    private static let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "remote-scan")

    /// Lists, diffs and re-snapshots each known container. `list` takes an
    /// rclone path (`""` for the root) and returns its entries.
    static func scan(
        remoteName: String,
        list: @escaping @Sendable (String) async throws -> [FileItem]
    ) async -> Outcome {
        let root = NSFileProviderItemIdentifier.rootContainer.rawValue
        let visits = await RemoteChangeWalk.run(
            root: root,
            isKnown: { raw in
                SyncSnapshotStore.hasSnapshot(remoteName: remoteName, containerIdentifier: NSFileProviderItemIdentifier(raw))
            },
            visit: { raw in await visit(raw, remoteName: remoteName, list: list) }
        )
        return outcome(of: visits)
    }

    /// Lists, diffs and re-snapshots only `containers` (the hot folders,
    /// #76), four at a time. Folders without a snapshot are skipped.
    static func scan(
        containers: [String],
        remoteName: String,
        list: @escaping @Sendable (String) async throws -> [FileItem]
    ) async -> Outcome {
        let known = containers.filter {
            SyncSnapshotStore.hasSnapshot(remoteName: remoteName, containerIdentifier: NSFileProviderItemIdentifier($0))
        }
        let visits = await RemoteChangeWalk.visitAll(known) { raw in
            await visit(raw, remoteName: remoteName, list: list)
        }
        return outcome(of: visits)
    }

    private static func outcome(of visits: [RemoteChangeVisit<UncheckedItems>]) -> Outcome {
        var outcome = Outcome(listedContainers: visits.count)
        for visit in visits {
            outcome.updated.append(contentsOf: visit.payload.items)
            outcome.deleted.append(contentsOf: visit.diff.deleted.map { NSFileProviderItemIdentifier($0) })
        }
        return outcome
    }

    private static func visit(
        _ raw: String,
        remoteName: String,
        list: @Sendable (String) async throws -> [FileItem]
    ) async -> RemoteChangeVisit<UncheckedItems>? {
        let container = NSFileProviderItemIdentifier(raw)
        let path = SyncSnapshotStore.remotePath(of: container, remoteName: remoteName)
        let files: [FileItem]
        do {
            files = try await list(path)
        } catch {
            logger.info("remote scan: skipped a folder whose listing failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let records = SyncSnapshotStore.buildRecords(from: files, parentIdentifier: container, remoteName: remoteName)
        let (diff, _) = SyncSnapshotStore.diffAndPersist(
            remoteName: remoteName, containerIdentifier: container, current: records
        )
        for folder in diff.deletedFolders {
            SyncSnapshotStore.removeSnapshot(remoteName: remoteName, containerIdentifier: folder)
        }
        return RemoteChangeVisit(
            container: raw,
            listing: records.map(\.record),
            diff: RemoteChangeDiff.Result(
                changed: diff.updated.map(\.itemIdentifier.rawValue),
                deleted: diff.deletedIdentifiers.map(\.rawValue),
                deletedFolders: diff.deletedFolders.map(\.rawValue)
            ),
            payload: UncheckedItems(items: diff.updated)
        )
    }
}

/// `FileProviderItem` is `@unchecked Sendable`; the array wrapper just
/// names that for the generic payload.
struct UncheckedItems: Sendable {
    let items: [FileProviderItem]
}
