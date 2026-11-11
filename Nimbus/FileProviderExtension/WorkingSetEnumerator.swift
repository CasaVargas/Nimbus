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
/// system then asks again and the scan runs.
///
/// Listing the working set returns every item in every folder the system
/// has listed (read from the snapshots, no network). The system indexes
/// those items in Spotlight, downloaded or not. An anchor from a build that
/// listed nothing is expired once, so existing domains re-list.
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

    /// Items per page of the working-set listing.
    static let pageSize = 500

    /// The listing, built on the first page and kept for the rest so a
    /// large cloud isn't re-walked per page.
    private var listing: [WorkingSetListing.Entry]?

    func invalidate() { listing = nil }

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let remoteName = domain.identifier.rawValue
        let offset = Self.offset(of: page)
        if offset == 0 || listing == nil {
            listing = WorkingSetListing.collect(root: NSFileProviderItemIdentifier.rootContainer.rawValue) { raw in
                SyncSnapshotStore.records(remoteName: remoteName, containerIdentifier: NSFileProviderItemIdentifier(raw))
            }
        }
        let entries = listing ?? []
        let start = min(offset, entries.count)
        let end = min(start + Self.pageSize, entries.count)
        let items = entries[start..<end].map {
            FileProviderItem(record: $0.record, parentIdentifier: NSFileProviderItemIdentifier($0.parent), remoteName: remoteName)
        }
        observer.didEnumerate(items)
        if end < entries.count {
            observer.finishEnumerating(upTo: Self.page(offset: end))
        } else {
            logger.info("working set \(remoteName, privacy: .public): listed \(entries.count) items")
            listing = nil
            observer.finishEnumerating(upTo: nil)
        }
    }

    /// Pages are `"nwsl"` + a little-endian Int64 offset. The system's own
    /// initial pages (and anything else) start from the top.
    private static let pageTag = Data("nwsl".utf8)

    static func page(offset: Int) -> NSFileProviderPage {
        var data = pageTag
        data.append(withUnsafeBytes(of: Int64(offset).littleEndian) { Data($0) })
        return NSFileProviderPage(data)
    }

    static func offset(of page: NSFileProviderPage) -> Int {
        let data = page.rawValue
        guard data.count == pageTag.count + 8, data.prefix(pageTag.count) == pageTag else { return 0 }
        let value = data.suffix(8).withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian
        return max(Int(value), 0)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let remoteName = domain.identifier.rawValue
        let pins = PinStore.shared?.latestSequence(domain: remoteName) ?? 0
        completionHandler(Self.anchor(pins: pins, generation: SyncSnapshotStore.remoteGeneration(remoteName: remoteName)))
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        let remoteName = domain.identifier.rawValue
        let decoded = WorkingSetAnchor.decode(syncAnchor.rawValue)
        guard decoded.format >= WorkingSetAnchor.currentFormat else {
            // Anchored by a build whose listing was empty: re-list so every
            // known item reaches Spotlight.
            logger.info("working set \(remoteName, privacy: .public): anchor predates the full listing, expiring it")
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
            return
        }
        let since = decoded.pinSequence
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
            // Folders listed for the first time since the last pass: report
            // their entries so Spotlight indexes them.
            var reported = Set(outcome.updated.map(\.itemIdentifier))
            var firstListed: [NSFileProviderItem] = []
            for container in SyncSnapshotStore.takeNewlyListed(remoteName: remoteName) {
                for record in SyncSnapshotStore.records(remoteName: remoteName, containerIdentifier: container) ?? []
                where reported.insert(NSFileProviderItemIdentifier(record.identifier)).inserted {
                    firstListed.append(FileProviderItem(record: record, parentIdentifier: container, remoteName: remoteName))
                }
            }
            var generation = SyncSnapshotStore.remoteGeneration(remoteName: remoteName)
            if outcome.hasChanges || !firstListed.isEmpty {
                generation = SyncSnapshotStore.bumpRemoteGeneration(remoteName: remoteName)
                if !outcome.updated.isEmpty { box.observer.didUpdate(outcome.updated) }
                if !firstListed.isEmpty { box.observer.didUpdate(firstListed) }
                if !outcome.deleted.isEmpty { box.observer.didDeleteItems(withIdentifiers: outcome.deleted) }
            }
            logger.info("working set \(remoteName, privacy: .public): scanned \(outcome.listedContainers) folders, \(outcome.updated.count) updated, \(outcome.deleted.count) deleted, \(firstListed.count) from first listings")
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
