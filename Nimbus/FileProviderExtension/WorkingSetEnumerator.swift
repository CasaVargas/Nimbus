import FileProvider
import RcloneKit
import os

/// The working set. For an `NSFileProviderReplicatedExtension` this is the
/// ONLY container the system accepts signals for and asks for changes, so
/// every change the system should learn about after a folder's first
/// listing is reported here:
///
/// - Keep Downloaded: a pin changes nothing on the server, so `PinStore`
///   keeps a change log and each changed item is reported with its new
///   content policy.
/// - Server-side changes: `RemoteChangeScanner` re-lists every folder the
///   system already knows about and diffs it against its snapshot.
///
/// The sync anchor is `WorkingSetAnchor`: (pin log sequence, remote
/// generation). Pin changes are reported on their own with
/// `moreComing: true`, so Keep Downloaded doesn't wait on a scan; the
/// system then asks again and the scan runs. Listing the working set stays
/// empty, as before: Nimbus doesn't track a working set of its own.
final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "working-set")
    private let domain: NSFileProviderDomain
    private let fetchItem: @Sendable (NSFileProviderItemIdentifier) async throws -> FileProviderItem
    private let listFiles: @Sendable (String) async throws -> [FileItem]

    init(domain: NSFileProviderDomain,
         fetchItem: @escaping @Sendable (NSFileProviderItemIdentifier) async throws -> FileProviderItem,
         listFiles: @escaping @Sendable (String) async throws -> [FileItem]) {
        self.domain = domain
        self.fetchItem = fetchItem
        self.listFiles = listFiles
    }

    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let remoteName = domain.identifier.rawValue
        let pins = PinStore.shared?.latestSequence(domain: remoteName) ?? 0
        completionHandler(Self.anchor(pins: pins, generation: SyncSnapshotStore.remoteGeneration(remoteName: remoteName)))
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        let remoteName = domain.identifier.rawValue
        let since = WorkingSetAnchor.decode(syncAnchor.rawValue).pinSequence
        guard let store = PinStore.shared, let changes = store.changes(domain: remoteName, after: since) else {
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
            return
        }
        let box = ObserverBox(observer: observer)
        let logger = self.logger

        if !changes.identifiers.isEmpty {
            let fetchItem = self.fetchItem
            let rootItem = FileProviderItem.rootContainer(domain: domain)
            Task {
                var updated: [NSFileProviderItem] = []
                for raw in changes.identifiers {
                    if raw == NSFileProviderItemIdentifier.rootContainer.rawValue {
                        updated.append(rootItem)
                        continue
                    }
                    do {
                        updated.append(try await fetchItem(NSFileProviderItemIdentifier(raw)))
                    } catch {
                        // Gone since it was pinned (deleted or moved): nothing to update.
                        logger.info("working set: skipped a changed pin that no longer resolves")
                    }
                }
                if !updated.isEmpty { box.observer.didUpdate(updated) }
                let generation = SyncSnapshotStore.remoteGeneration(remoteName: remoteName)
                // moreComing: the system asks again from this anchor, and
                // that call (no pin changes left) runs the remote scan.
                box.observer.finishEnumeratingChanges(
                    upTo: Self.anchor(pins: changes.latest, generation: generation), moreComing: true
                )
            }
            return
        }

        let listFiles = self.listFiles
        Task {
            let outcome = await RemoteChangeScanner.scan(remoteName: remoteName, list: listFiles)
            var generation = SyncSnapshotStore.remoteGeneration(remoteName: remoteName)
            if outcome.hasChanges {
                generation = SyncSnapshotStore.bumpRemoteGeneration(remoteName: remoteName)
                if !outcome.updated.isEmpty { box.observer.didUpdate(outcome.updated) }
                if !outcome.deleted.isEmpty { box.observer.didDeleteItems(withIdentifiers: outcome.deleted) }
            }
            logger.info("working set \(remoteName, privacy: .public): scanned \(outcome.listedContainers) folders, \(outcome.updated.count) updated, \(outcome.deleted.count) deleted")
            box.observer.finishEnumeratingChanges(
                upTo: Self.anchor(pins: changes.latest, generation: generation), moreComing: false
            )
        }
    }

    static func anchor(pins: Int, generation: Int) -> NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(WorkingSetAnchor.encode(pinSequence: pins, remoteGeneration: generation))
    }
}

private struct ObserverBox: @unchecked Sendable {
    let observer: any NSFileProviderChangeObserver
}
