import FileProvider
import RcloneKit
import os

// MARK: - Finder thumbnails

/// Finder asks for thumbnails of items that aren't downloaded yet; once a
/// file is on disk Finder draws its own. Photos and PDFs up to
/// `ThumbnailPolicy.maxSourceBytes` are downloaded to a temp file, drawn
/// at the requested size, and the temp file is deleted. Everything else
/// keeps the generic icon. The system caches what we return until the
/// item's content version changes; `ThumbnailCache` keeps them across
/// that cache being purged.
extension FileProviderExtension: NSFileProviderThumbnailing {
    func fetchThumbnails(
        for itemIdentifiers: [NSFileProviderItemIdentifier],
        requestedSize size: CGSize,
        perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, (any Error)?) -> Void,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        refreshPort()
        let context = ThumbnailContext(
            rclone: rclone,
            remoteName: domain.identifier.rawValue,
            maxPixel: max(1, Int(max(size.width, size.height).rounded(.up))),
            cache: thumbnailCache(for: domain),
            limiter: thumbnailLimiter,
            logger: logger
        )
        let gate = ThumbnailCompletionGate(perItem: perThumbnailCompletionHandler, finish: completionHandler)
        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))

        let task = Task { @Sendable in
            await withTaskGroup(of: Void.self) { group in
                for identifier in itemIdentifiers {
                    group.addTask {
                        let (data, error) = await context.thumbnail(for: identifier)
                        gate.deliver(identifier, data, error)
                        progress.completedUnitCount += 1
                    }
                }
            }
            gate.finish(nil)
        }
        progress.cancellationHandler = {
            task.cancel()
            gate.finish(CocoaError(.userCancelled))
        }
        return progress
    }

    /// One folder per cloud in the extension's Caches directory: it survives
    /// extension restarts (unlike the temp directory `invalidate()` empties),
    /// and macOS may purge it under disk pressure, which a cache can afford.
    /// Not the domain's `stateDirectoryURL()`: writing there fails with
    /// EPERM from the sandboxed extension.
    private func thumbnailCache(for domain: NSFileProviderDomain) -> ThumbnailCache? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let name = domain.identifier.rawValue
        let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return ThumbnailCache(directory: caches
            .appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true))
    }
}

/// Everything one thumbnail request needs, captured once so the work can
/// run off the extension object.
private struct ThumbnailContext: Sendable {
    let rclone: RcloneClient
    let remoteName: String
    let maxPixel: Int
    let cache: ThumbnailCache?
    let limiter: AsyncLimiter
    let logger: Logger

    /// (nil, nil) means "no thumbnail": Finder keeps the generic icon.
    func thumbnail(for identifier: NSFileProviderItemIdentifier) async -> (Data?, (any Error)?) {
        do {
            let item = try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "thumbnail.stat") {
                try await FileProviderExtension.fetchItemStatic(rclone: rclone, identifier: identifier, remoteName: remoteName)
            }
            guard let kind = ThumbnailPolicy.kind(for: item.contentType, size: item.documentSize?.int64Value) else {
                return (nil, nil)
            }
            let key = ThumbnailCache.key(identifier: identifier.rawValue,
                                         contentVersion: item.itemVersion.contentVersion,
                                         maxPixel: maxPixel)
            if let cached = cache?.data(for: key) { return (cached, nil) }

            await limiter.acquire()
            let result: Result<Data?, any Error>
            do {
                result = .success(try await render(identifier: identifier, kind: kind))
            } catch {
                result = .failure(error)
            }
            await limiter.release()

            let data = try result.get()
            if let data, let cache {
                do { try cache.store(data, for: key) } catch {
                    logger.error("thumbnail cache write failed: \(error)")
                }
            }
            return (data, nil)
        } catch is CancellationError {
            return (nil, CocoaError(.userCancelled))
        } catch {
            logger.error("thumbnail failed for \(identifier.rawValue, privacy: .private): \(error)")
            return (nil, FileProviderExtension.mapToFileProviderError(error))
        }
    }

    private func render(identifier: NSFileProviderItemIdentifier, kind: ThumbnailPolicy.Kind) async throws -> Data? {
        try Task.checkCancellation()
        let remotePath = FileProviderExtension.extractPathStatic(from: identifier, remoteName: remoteName)
        let directory = FileProviderExtension.tempDirectory().appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let localURL = directory.appendingPathComponent(
            "\(UUID().uuidString)_\((remotePath as NSString).lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: localURL) }

        try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "thumbnail.download") {
            try await rclone.downloadFile(fs: "\(remoteName):", remote: remotePath, to: localURL)
        }
        try Task.checkCancellation()
        return ThumbnailRenderer.png(from: localURL, kind: kind, maxPixel: maxPixel)
    }
}

/// Calls the system's handlers safely from many tasks: per-item results
/// stop once the request has finished (completed or cancelled), and the
/// final handler runs exactly once.
private final class ThumbnailCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let perItem: (NSFileProviderItemIdentifier, Data?, (any Error)?) -> Void
    private let onFinish: ((any Error)?) -> Void

    init(perItem: @escaping (NSFileProviderItemIdentifier, Data?, (any Error)?) -> Void,
         finish: @escaping ((any Error)?) -> Void) {
        self.perItem = perItem
        self.onFinish = finish
    }

    func deliver(_ identifier: NSFileProviderItemIdentifier, _ data: Data?, _ error: (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        perItem(identifier, data, error)
    }

    func finish(_ error: (any Error)?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        onFinish(error)
    }
}
