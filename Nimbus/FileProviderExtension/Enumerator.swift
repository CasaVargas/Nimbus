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

        let boxedObserver = UncheckedBox(value: observer)
        Task { @Sendable in
            do {
                let files = try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)
                let items = files.map { FileProviderItem(from: $0, parentIdentifier: parentId, remoteName: remoteName) }

                boxedObserver.value.didEnumerate(items)
                boxedObserver.value.finishEnumerating(upTo: nil)
            } catch {
                logger.error("enumerateItems failed: \(error)")
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
                let files = try await rclone.listFiles(fs: "\(remoteName):", remote: remotePath)
                let items = files.map { FileProviderItem(from: $0, parentIdentifier: parentId, remoteName: remoteName) as NSFileProviderItem }

                if !items.isEmpty {
                    boxedObserver.value.didUpdate(items)
                }

                let anchorData = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
                boxedObserver.value.finishEnumeratingChanges(
                    upTo: NSFileProviderSyncAnchor(anchorData),
                    moreComing: false
                )
            } catch {
                logger.error("enumerateChanges failed: \(error)")
                boxedObserver.value.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let data = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
        completionHandler(NSFileProviderSyncAnchor(data))
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
}
