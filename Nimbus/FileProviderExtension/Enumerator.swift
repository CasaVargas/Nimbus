import FileProvider
import RcloneKit
import os

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let rclone: RcloneClient
    private let domain: NSFileProviderDomain
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "enumerator")

    /// Items per page. rclone's `operations/list` has no server-side paging
    /// concept (it always returns the full directory listing in one JSON
    /// body), so pages are sliced client-side out of that single response.
    /// For a localhost daemon the extra bytes-on-the-wire cost of
    /// re-fetching the full listing per page is negligible, and this keeps
    /// the implementation simple/stateless instead of caching listings
    /// across `enumerateItems` calls.
    private static let pageSize = 500

    init(
        containerIdentifier: NSFileProviderItemIdentifier,
        rclone: RcloneClient,
        domain: NSFileProviderDomain
    ) {
        self.containerIdentifier = containerIdentifier
        self.rclone = rclone
        self.domain = domain
    }

    func invalidate() {}

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let remoteName = domain.identifier.rawValue
        let remotePath = extractPath()
        let parentId = containerIdentifier
        let rclone = self.rclone
        let logger = self.logger
        let offset = Self.offset(from: page)

        let boxedObserver = UncheckedBox(value: observer)
        Task { @Sendable in
            do {
                let files = try await FileProviderRetry.withRetry(
                    rclone: rclone,
                    logger: logger,
                    operation: "enumerateItems(\(remoteName):\(remotePath))"
                ) {
                    try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)
                }

                let records = SyncSnapshotStore.buildRecords(
                    from: files,
                    containerPath: remotePath,
                    parentIdentifier: parentId,
                    remoteName: remoteName
                )
                // Seed the change-tracking baseline from this full listing so
                // the next `enumerateChanges` call has something real to diff
                // against instead of treating every item as newly added.
                SyncSnapshotStore.seed(remoteName: remoteName, containerIdentifier: parentId, current: records)

                let start = min(max(offset, 0), records.count)
                let end = min(start + Self.pageSize, records.count)
                let pageItems = records[start..<end].map(\.item)

                boxedObserver.value.didEnumerate(pageItems)
                if end < records.count {
                    boxedObserver.value.finishEnumerating(upTo: Self.page(for: end))
                } else {
                    boxedObserver.value.finishEnumerating(upTo: nil)
                }
            } catch {
                logger.error("enumerateItems exhausted retries for \(remoteName):\(remotePath): \(String(describing: error))")
                boxedObserver.value.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        let remoteName = domain.identifier.rawValue
        let remotePath = extractPath()
        let parentId = containerIdentifier
        let rclone = self.rclone
        let logger = self.logger

        let boxedObserver = UncheckedBox(value: observer)
        Task { @Sendable in
            do {
                let files = try await FileProviderRetry.withRetry(
                    rclone: rclone,
                    logger: logger,
                    operation: "enumerateChanges(\(remoteName):\(remotePath))"
                ) {
                    try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)
                }

                let records = SyncSnapshotStore.buildRecords(
                    from: files,
                    containerPath: remotePath,
                    parentIdentifier: parentId,
                    remoteName: remoteName
                )
                let (diff, anchor) = SyncSnapshotStore.diffAndPersist(
                    remoteName: remoteName,
                    containerIdentifier: parentId,
                    current: records
                )

                if !diff.updated.isEmpty {
                    boxedObserver.value.didUpdate(diff.updated)
                }
                if !diff.deletedIdentifiers.isEmpty {
                    boxedObserver.value.didDeleteItems(withIdentifiers: diff.deletedIdentifiers)
                }

                boxedObserver.value.finishEnumeratingChanges(upTo: anchor, moreComing: false)
            } catch {
                logger.error("enumerateChanges failed for \(remoteName):\(remotePath): \(String(describing: error))")
                boxedObserver.value.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let remoteName = domain.identifier.rawValue
        completionHandler(SyncSnapshotStore.currentAnchor(remoteName: remoteName, containerIdentifier: containerIdentifier))
    }

    private func extractPath() -> String {
        let raw = containerIdentifier.rawValue
        let remoteName = domain.identifier.rawValue
        let prefix = "\(remoteName):"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        if containerIdentifier == .rootContainer {
            return ""
        }
        return raw
    }

    // MARK: - Client-side paging

    private static func offset(from page: NSFileProviderPage) -> Int {
        let raw = page.rawValue
        guard raw.count == MemoryLayout<Int>.size else { return 0 }
        return raw.withUnsafeBytes { $0.load(as: Int.self) }
    }

    private static func page(for offset: Int) -> NSFileProviderPage {
        NSFileProviderPage(withUnsafeBytes(of: offset) { Data($0) })
    }
}
