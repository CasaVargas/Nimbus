import FileProvider
import os

/// Enumerator for the two synthetic system containers every
/// `NSFileProviderReplicatedExtension` must be able to enumerate:
/// `.workingSet` and `.trashContainer`.
///
/// Nimbus doesn't track a working set of materialized items independent of
/// the browsed hierarchy, and rclone has no universal trash/recycle-bin
/// concept across the 50+ backends it fronts (deletes go straight through
/// `operations/deletefile`/`operations/purge`), so both containers are
/// legitimately empty for every domain. Returning an empty page immediately
/// — rather than routing through `FileProviderEnumerator`, which would try
/// to `operations/list` the literal identifier string
/// (`"NSFileProviderWorkingSetContainerItemIdentifier"`, etc.) as if it were
/// a remote path — avoids five retries × linear backoff (~10s of wasted
/// work) on every domain launch, since `FileProviderBridge` signals
/// `.workingSet` right after registering a domain.
final class SystemContainerEnumerator: NSObject, NSFileProviderEnumerator {
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "system-container-enumerator")
    private let containerIdentifier: NSFileProviderItemIdentifier

    init(containerIdentifier: NSFileProviderItemIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        logger.debug("Enumerating synthetic container \(self.containerIdentifier.rawValue) as empty")
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: Self.emptyAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.emptyAnchor)
    }

    /// A single fixed anchor — the container never changes, so there's
    /// nothing to diff and no reason to mint a new anchor on each call.
    private static let emptyAnchor = NSFileProviderSyncAnchor(Data([0]))
}
