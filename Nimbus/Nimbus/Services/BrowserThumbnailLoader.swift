import CoreGraphics
import Foundation
import ImageIO
import RcloneKit
import UniformTypeIdentifiers

/// One picture the browser wants: which file, and how large to draw it.
struct ThumbnailRequest: Hashable, Sendable {
    let remote: String
    /// Full path from the remote's root.
    let path: String
    let name: String
    let size: Int64
    let modTime: Date?
    let maxPixel: Int

    init(remote: String, path: String, name: String, size: Int64, modTime: Date?, maxPixel: Int) {
        self.remote = remote
        self.path = path
        self.name = name
        self.size = size
        self.modTime = modTime
        self.maxPixel = maxPixel
    }

    init(file: FileItem, remote: String, maxPixel: Int) {
        // `FileItem.path` is relative to the listed folder; the qualified
        // path ("remote:dir/leaf") carries the full one.
        let prefix = "\(remote):"
        let path = file.qualifiedRemotePath.hasPrefix(prefix)
            ? String(file.qualifiedRemotePath.dropFirst(prefix.count))
            : file.path
        // A folder never gets a picture, whatever its name ends in.
        self.init(remote: remote, path: path, name: file.name, size: file.isDir ? -1 : file.size,
                  modTime: file.modTime, maxPixel: maxPixel)
    }

    /// nil when the file keeps its icon: the same rule Finder thumbnails use.
    var kind: ThumbnailPolicy.Kind? {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        return ThumbnailPolicy.kind(for: type, size: size)
    }

    /// Size and date stand in for a content version: an edited file misses
    /// the cache rather than showing its old picture.
    var cacheKey: String {
        let version = "\(size)|\(modTime?.timeIntervalSince1970 ?? 0)"
        return ThumbnailCache.key(identifier: "\(remote):\(path)", contentVersion: Data(version.utf8),
                                  maxPixel: maxPixel)
    }
}

/// What the gallery draws pictures from. A protocol so tests and previews
/// can answer without a cloud.
protocol GalleryThumbnailProviding: Sendable {
    /// A picture already in memory, without waiting. Lets a cell that
    /// scrolls back into view draw at once instead of flashing its icon.
    func cachedImage(for request: ThumbnailRequest) -> CGImage?
    /// The picture, fetched and drawn if needed. nil when the file keeps
    /// its icon or anything went wrong.
    func image(for request: ThumbnailRequest) async -> CGImage?
}

/// Draws thumbnails for the in-app browser. rclone has no thumbnail call,
/// so a picture costs one download of the file; this keeps that to files
/// `ThumbnailPolicy` allows, three at a time, once per file version.
actor BrowserThumbnailLoader: GalleryThumbnailProviding {
    private let client: any RcloneClientProtocol
    private let cache: ThumbnailCache?
    private let limiter: AsyncLimiter
    private let memory = ThumbnailMemoryCache()

    init(client: any RcloneClientProtocol, cache: ThumbnailCache?, limiter: AsyncLimiter = AsyncLimiter(limit: 3)) {
        self.client = client
        self.cache = cache
        self.limiter = limiter
    }

    /// The app's Caches folder: macOS may purge it under disk pressure,
    /// which a cache can afford. Under the bundle identifier, because the
    /// app isn't sandboxed and Caches is then the one every app shares.
    static func defaultCache() -> ThumbnailCache? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
            ThumbnailCache(directory: cacheDirectory(in: $0))
        }
    }

    static func cacheDirectory(in caches: URL, bundleID: String? = Bundle.main.bundleIdentifier) -> URL {
        caches
            .appendingPathComponent(bundleID ?? "app.casavargas.nimbus", isDirectory: true)
            .appendingPathComponent("BrowserThumbnails", isDirectory: true)
    }

    nonisolated func cachedImage(for request: ThumbnailRequest) -> CGImage? {
        memory.image(for: request.cacheKey)
    }

    func image(for request: ThumbnailRequest) async -> CGImage? {
        guard let kind = request.kind else { return nil }
        let key = request.cacheKey
        if let hit = memory.image(for: key) { return hit }
        if let data = cache?.data(for: key), let image = Self.decode(data) {
            memory.store(image, for: key)
            return image
        }

        await limiter.acquire()
        let image = await fetch(request, kind: kind, key: key)
        await limiter.release()
        return image
    }

    private func fetch(_ request: ThumbnailRequest, kind: ThumbnailPolicy.Kind, key: String) async -> CGImage? {
        // The cell may have scrolled away while this waited its turn, or
        // another request for the same picture may have finished.
        guard !Task.isCancelled else { return nil }
        if let hit = memory.image(for: key) { return hit }

        guard let url = try? await client.downloadToTemp(remote: request.remote, path: request.path) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let maxPixel = request.maxPixel
        let data = await Task.detached(priority: .utility) {
            ThumbnailRenderer.png(from: url, kind: kind, maxPixel: maxPixel)
        }.value
        guard let data, let image = Self.decode(data) else { return nil }
        try? cache?.store(data, for: key)
        memory.store(image, for: key)
        return image
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Decoded pictures for this session. `NSCache` is thread-safe and drops
/// entries under memory pressure.
private final class ThumbnailMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImage>()

    init() {
        cache.countLimit = 600
    }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: CGImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
