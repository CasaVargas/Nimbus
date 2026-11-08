import FileProvider
import RcloneKit
import os

/// The working set. For an `NSFileProviderReplicatedExtension` this is the
/// ONLY container the system accepts signals for, so it is where changes
/// the system can't discover by listing have to be reported.
///
/// Today that means Keep Downloaded: a pin changes nothing on the server,
/// so `PinStore` keeps a change log and this enumerator reports each
/// changed item (with its new content policy) as updated. The sync anchor
/// is the log's sequence number. Listing the working set stays empty, as
/// before: Nimbus doesn't track a working set of its own.
final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "working-set")
    private let domain: NSFileProviderDomain
    private let fetchItem: @Sendable (NSFileProviderItemIdentifier) async throws -> FileProviderItem

    init(domain: NSFileProviderDomain,
         fetchItem: @escaping @Sendable (NSFileProviderItemIdentifier) async throws -> FileProviderItem) {
        self.domain = domain
        self.fetchItem = fetchItem
    }

    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let latest = PinStore.shared?.latestSequence(domain: domain.identifier.rawValue) ?? 0
        completionHandler(Self.anchor(latest))
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        let remoteName = domain.identifier.rawValue
        let since = Self.sequence(of: syncAnchor)
        guard let store = PinStore.shared, let changes = store.changes(domain: remoteName, after: since) else {
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
            return
        }
        guard !changes.identifiers.isEmpty else {
            observer.finishEnumeratingChanges(upTo: Self.anchor(changes.latest), moreComing: false)
            return
        }
        let box = ObserverBox(observer: observer)
        let fetchItem = self.fetchItem
        let logger = self.logger
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
            box.observer.finishEnumeratingChanges(upTo: Self.anchor(changes.latest), moreComing: false)
        }
    }

    static func anchor(_ sequence: Int) -> NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(withUnsafeBytes(of: Int64(sequence).littleEndian) { Data($0) })
    }

    static func sequence(of anchor: NSFileProviderSyncAnchor) -> Int {
        let data = anchor.rawValue
        guard data.count == 8 else { return 0 }
        return Int(data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian)
    }
}

private struct ObserverBox: @unchecked Sendable {
    let observer: any NSFileProviderChangeObserver
}
