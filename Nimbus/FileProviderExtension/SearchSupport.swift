import FileProvider
import RcloneKit
import os

// System search (Spotlight, Finder) asks the extension directly, so files in
// folders nobody has opened are found too. Needs macOS 26 and a domain with
// `supportsStringSearchRequest` (set by the app's `FileProviderBridge`).

@available(macOS 26.0, *)
extension FileProviderItem: NSFileProviderSearchResult {}

@available(macOS 26.0, *)
extension FileProviderExtension: NSFileProviderSearching {
    func searchEnumerator(for request: NSFileProviderStringSearchRequest) -> any NSFileProviderSearchEnumerator {
        refreshPort()
        return CloudSearchEnumerator(
            query: request.query,
            limit: request.desiredNumberOfResults,
            remoteName: domain.identifier.rawValue,
            rclone: rclone
        )
    }
}

/// One system search over one cloud: a name search run by rclone (see
/// `RemoteSearch`), delivered in a single page. `invalidate()` (the person
/// typed another character, or the system is done) stops the rclone job.
@available(macOS 26.0, *)
final class CloudSearchEnumerator: NSObject, NSFileProviderSearchEnumerator, @unchecked Sendable {
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "search")
    private let query: String
    private let limit: Int
    private let remoteName: String
    private let rclone: RcloneClient
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(query: String, limit: Int, remoteName: String, rclone: RcloneClient) {
        self.query = query
        self.limit = limit
        self.remoteName = remoteName
        self.rclone = rclone
    }

    func invalidate() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }

    func enumerateSearchResults(for observer: any NSFileProviderSearchEnumerationObserver, startingAt page: NSFileProviderPage?) {
        let box = SearchObserverBox(observer: observer)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // One page only: everything comes back from the first call.
        guard page == nil, !query.isEmpty else {
            observer.finishEnumerating(upTo: nil)
            return
        }
        let cap = max(1, min(limit > 0 ? limit : Int.max, observer.maximumNumberOfResultsPerPage))
        let remoteName = remoteName
        let rclone = rclone
        let logger = logger
        let task = Task {
            do {
                let files = try await rclone.search(fs: "\(remoteName):", query: query)
                let results = files.prefix(cap).map { file in
                    FileProviderItem(from: file, parentIdentifier: Self.parent(of: file.path, remoteName: remoteName), remoteName: remoteName)
                }
                logger.info("search \(remoteName, privacy: .public): \(files.count) matches, \(results.count) returned")
                box.observer.didEnumerate(Array(results))
                box.observer.finishEnumerating(upTo: nil)
            } catch is CancellationError {
                box.observer.finishEnumeratingWithError(CocoaError(.userCancelled))
            } catch {
                logger.error("search \(remoteName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                box.observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
            }
        }
        lock.withLock {
            self.task?.cancel()
            self.task = task
        }
    }

    /// Identifier of the folder holding `path` (a path from the remote root).
    static func parent(of path: String, remoteName: String) -> NSFileProviderItemIdentifier {
        let parentPath = (path as NSString).deletingLastPathComponent
        return parentPath.isEmpty ? .rootContainer : NSFileProviderItemIdentifier("\(remoteName):\(parentPath)")
    }
}

@available(macOS 26.0, *)
private struct SearchObserverBox: @unchecked Sendable {
    let observer: any NSFileProviderSearchEnumerationObserver
}
