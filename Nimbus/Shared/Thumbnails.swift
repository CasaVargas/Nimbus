import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Which cloud files get a Finder thumbnail before they're downloaded.
/// Kept free of FileProvider types so the app's tests can cover it.
enum ThumbnailPolicy {
    /// Larger files keep the generic icon: drawing one shouldn't cost a
    /// big download.
    static let maxSourceBytes: Int64 = 20 * 1024 * 1024

    enum Kind: Equatable { case image, pdf }

    /// nil when the file keeps its generic icon: not a photo or PDF, too
    /// large, or of unknown size (rclone reports -1 for some services).
    static func kind(for type: UTType, size: Int64?) -> Kind? {
        guard let size, size > 0, size <= maxSourceBytes else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return nil
    }
}

/// Draws a thumbnail as PNG data, no larger than `maxPixel` on its long side.
enum ThumbnailRenderer {
    static func png(from url: URL, kind: ThumbnailPolicy.Kind, maxPixel: Int) -> Data? {
        guard maxPixel > 0 else { return nil }
        let image: CGImage? = switch kind {
        case .image: imageThumbnail(url, maxPixel: maxPixel)
        case .pdf: pdfThumbnail(url, maxPixel: maxPixel)
        }
        return image.flatMap(encodePNG)
    }

    private static func imageThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pdfThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let pageSize = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }

        let scale = CGFloat(maxPixel) / max(pageSize.width, pageSize.height)
        let width = max(1, Int((pageSize.width * scale).rounded(.down)))
        let height = max(1, Int((pageSize.height * scale).rounded(.down)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Pages are usually drawn on white; a transparent thumbnail looks broken in Finder.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize),
                                                     rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Thumbnails already drawn, so scrolling back through a folder doesn't
/// download the photos again. One file per thumbnail; reading an entry
/// marks it used, and storing prunes the least recently used entries to
/// stay under `limit` bytes. A changed file has a new content version, so
/// it misses the cache rather than showing a stale picture.
final class ThumbnailCache: @unchecked Sendable {
    static let defaultLimit: Int64 = 200 * 1024 * 1024

    private let directory: URL
    private let limit: Int64
    private let lock = NSLock()

    init(directory: URL, limit: Int64 = ThumbnailCache.defaultLimit) {
        self.directory = directory
        self.limit = limit
    }

    static func key(identifier: String, contentVersion: Data, maxPixel: Int) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(identifier.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: contentVersion)
        hasher.update(data: Data([0]))
        hasher.update(data: Data(String(maxPixel).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func data(for key: String) -> Data? {
        let url = directory.appendingPathComponent(key)
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// Throws when the entry can't be written; the thumbnail is still
    /// returned to Finder, just not kept.
    func store(_ data: Data, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(key), options: .atomic)
        prune()
    }

    /// Caller holds `lock`.
    private func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        else { return }
        var entries = urls.compactMap { url -> (url: URL, size: Int64, used: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        entries.sort { $0.used < $1.used }
        for entry in entries where total > limit {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// At most `limit` callers between `acquire()` and `release()` at once;
/// the rest wait in order.
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            // Hand the slot straight to the next waiter.
            waiting.removeFirst().resume()
        }
    }
}
