import FileProvider
import os.log

// @unchecked Sendable: all stored properties are set at init and never mutated
// (cachedItems is only accessed from Task blocks serialized by the FP daemon);
// NSFileProviderEnumerator is called from the File Provider daemon which manages
// its own concurrency guarantees.
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {

    private let containerIdentifier: NSFileProviderItemIdentifier
    private let rclone: RcloneClient
    private let domain: NSFileProviderDomain

    /// Cached snapshot of the last enumeration for change diffing
    /// Key: item identifier raw value, Value: raw rclone entry
    private var cachedEntries: [String: [String: Any]] = [:]
    private var lastEnumerationDate: Date = .distantPast

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
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                let remotePath = self.remotePath(for: containerIdentifier)
                let rawEntries = try await rclone.listDirectoryRaw(remotePath: remotePath)

                // Build cache and items
                var newCache: [String: [String: Any]] = [:]
                var items: [NSFileProviderItem] = []

                for entry in rawEntries {
                    guard let item = FileProviderItem.from(
                        rcloneEntry: entry,
                        parentIdentifier: containerIdentifier,
                        remoteName: rclone.remoteName
                    ) else { continue }

                    newCache[item.itemIdentifier.rawValue] = entry
                    items.append(item)
                }

                self.cachedEntries = newCache
                self.lastEnumerationDate = Date()

                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                logger.error("enumerateItems failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                let remotePath = self.remotePath(for: containerIdentifier)
                let rawEntries = try await rclone.listDirectoryRaw(remotePath: remotePath)

                var newCache: [String: [String: Any]] = [:]
                var updatedItems: [NSFileProviderItem] = []
                var newIdentifiers = Set<String>()

                for entry in rawEntries {
                    guard let item = FileProviderItem.from(
                        rcloneEntry: entry,
                        parentIdentifier: containerIdentifier,
                        remoteName: rclone.remoteName
                    ) else { continue }

                    let key = item.itemIdentifier.rawValue
                    newIdentifiers.insert(key)
                    newCache[key] = entry

                    // Check if this item is new or modified
                    if let oldEntry = self.cachedEntries[key] {
                        let oldModTime = oldEntry["ModTime"] as? String ?? ""
                        let newModTime = entry["ModTime"] as? String ?? ""
                        let oldSize = oldEntry["Size"] as? Int64 ?? 0
                        let newSize = entry["Size"] as? Int64 ?? 0

                        if oldModTime != newModTime || oldSize != newSize {
                            updatedItems.append(item)
                        }
                    } else {
                        // New item
                        updatedItems.append(item)
                    }
                }

                // Find deleted items
                let deletedIdentifiers = Set(self.cachedEntries.keys).subtracting(newIdentifiers)
                let deletedIds = deletedIdentifiers.map { NSFileProviderItemIdentifier($0) }

                self.cachedEntries = newCache
                self.lastEnumerationDate = Date()

                if !updatedItems.isEmpty {
                    observer.didUpdate(updatedItems)
                }
                if !deletedIds.isEmpty {
                    observer.didDeleteItems(withIdentifiers: deletedIds)
                }

                let anchorData = "\(Date().timeIntervalSince1970)".data(using: .utf8)!
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(anchorData), moreComing: false)
            } catch {
                logger.error("enumerateChanges failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchorData = "\(lastEnumerationDate.timeIntervalSince1970)".data(using: .utf8)!
        completionHandler(NSFileProviderSyncAnchor(anchorData))
    }

    // MARK: - Helpers

    private func remotePath(for identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            return ""
        }
        let raw = identifier.rawValue
        if let colonIndex = raw.firstIndex(of: ":") {
            return String(raw[raw.index(after: colonIndex)...])
        }
        return raw
    }
}
