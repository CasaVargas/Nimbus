import FileProvider
import os.log

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    private let containerIdentifier: NSFileProviderItemIdentifier
    private let rclone: RcloneClient
    private let domain: NSFileProviderDomain

    init(containerIdentifier: NSFileProviderItemIdentifier,
         rclone: RcloneClient,
         domain: NSFileProviderDomain) {
        self.containerIdentifier = containerIdentifier
        self.rclone = rclone
        self.domain = domain
        super.init()
    }

    func invalidate() {
        // No-op: no long-running state to clean up
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                let remotePath = self.remotePath(for: containerIdentifier)
                let items = try await rclone.listDirectory(remotePath: remotePath, parentIdentifier: containerIdentifier)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                logger.error("enumerateItems failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // For v1 scaffold: report no changes, return current anchor
        // Full change enumeration will be implemented in Phase 2 iteration
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Simple timestamp-based anchor
        let anchorData = "\(Date().timeIntervalSince1970)".data(using: .utf8)!
        completionHandler(NSFileProviderSyncAnchor(anchorData))
    }

    // MARK: - Helpers

    /// Convert a File Provider item identifier to an rclone remote path
    private func remotePath(for identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            return ""
        }
        // Identifier is "remoteName:path/to/dir" — extract the path part after ":"
        let raw = identifier.rawValue
        if let colonIndex = raw.firstIndex(of: ":") {
            return String(raw[raw.index(after: colonIndex)...])
        }
        return raw
    }
}
