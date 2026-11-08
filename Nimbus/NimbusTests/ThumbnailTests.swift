import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Nimbus

@Suite("Thumbnails")
struct ThumbnailTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ThumbnailTests-\(UUID().uuidString)", isDirectory: true)

    // MARK: - Eligibility

    @Test func photosAndPDFsWithinTheLimitAreEligible() {
        #expect(ThumbnailPolicy.kind(for: .jpeg, size: 3_000_000) == .image)
        #expect(ThumbnailPolicy.kind(for: .heic, size: 1) == .image)
        #expect(ThumbnailPolicy.kind(for: .png, size: ThumbnailPolicy.maxSourceBytes) == .image)
        #expect(ThumbnailPolicy.kind(for: .pdf, size: 500_000) == .pdf)
    }

    @Test func otherTypesTooLargeOrUnknownSizesAreNot() {
        #expect(ThumbnailPolicy.kind(for: .jpeg, size: ThumbnailPolicy.maxSourceBytes + 1) == nil)
        #expect(ThumbnailPolicy.kind(for: .jpeg, size: nil) == nil)
        #expect(ThumbnailPolicy.kind(for: .jpeg, size: -1) == nil)
        #expect(ThumbnailPolicy.kind(for: .jpeg, size: 0) == nil)
        #expect(ThumbnailPolicy.kind(for: .mpeg4Movie, size: 1_000) == nil)
        #expect(ThumbnailPolicy.kind(for: .plainText, size: 1_000) == nil)
        #expect(ThumbnailPolicy.kind(for: .folder, size: 1_000) == nil)
    }

    // MARK: - Cache

    @Test func cacheKeyChangesWithIdentifierVersionAndSize() {
        let base = ThumbnailCache.key(identifier: "d:a.jpg", contentVersion: Data([1]), maxPixel: 256)
        #expect(base == ThumbnailCache.key(identifier: "d:a.jpg", contentVersion: Data([1]), maxPixel: 256))
        #expect(base != ThumbnailCache.key(identifier: "d:b.jpg", contentVersion: Data([1]), maxPixel: 256))
        #expect(base != ThumbnailCache.key(identifier: "d:a.jpg", contentVersion: Data([2]), maxPixel: 256))
        #expect(base != ThumbnailCache.key(identifier: "d:a.jpg", contentVersion: Data([1]), maxPixel: 512))
        #expect(!base.contains("/"))
    }

    @Test func storeAndRead() throws {
        let cache = ThumbnailCache(directory: directory)
        #expect(cache.data(for: "k") == nil)
        try cache.store(Data("png".utf8), for: "k")
        #expect(cache.data(for: "k") == Data("png".utf8))
    }

    @Test func pruneDropsTheLeastRecentlyUsedFirst() throws {
        let cache = ThumbnailCache(directory: directory, limit: 25)
        let ten = Data(repeating: 7, count: 10)
        try cache.store(ten, for: "old")
        try cache.store(ten, for: "middle")
        try age("old", by: 300)
        try age("middle", by: 200)
        // Reading "old" makes it the most recently used.
        #expect(cache.data(for: "old") != nil)
        try cache.store(ten, for: "new")   // 30 bytes > 25: one entry must go.
        #expect(cache.data(for: "middle") == nil)
        #expect(cache.data(for: "old") != nil)
        #expect(cache.data(for: "new") != nil)
    }

    @Test func anEntryLargerThanTheLimitIsNotKept() throws {
        let cache = ThumbnailCache(directory: directory, limit: 5)
        try cache.store(Data(repeating: 1, count: 10), for: "big")
        #expect(cache.data(for: "big") == nil)
    }

    // MARK: - Rendering

    @Test func rendersAnImageWithinTheRequestedSize() throws {
        let url = try writeImage(width: 1200, height: 800)
        let png = try #require(ThumbnailRenderer.png(from: url, kind: .image, maxPixel: 256))
        let size = try pixelSize(of: png)
        #expect(max(size.width, size.height) <= 256)
        #expect(size.width > size.height)
    }

    @Test func rendersThePDFsFirstPage() throws {
        let url = directory.appendingPathComponent("doc.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        context.endPDFPage()
        context.closePDF()

        let png = try #require(ThumbnailRenderer.png(from: url, kind: .pdf, maxPixel: 300))
        let size = try pixelSize(of: png)
        #expect(max(size.width, size.height) <= 300)
        #expect(size.height > size.width)
    }

    @Test func unreadableFilesGiveNoThumbnail() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: url)
        #expect(ThumbnailRenderer.png(from: url, kind: .image, maxPixel: 256) == nil)
        #expect(ThumbnailRenderer.png(from: url, kind: .pdf, maxPixel: 256) == nil)
    }

    // MARK: - Limiter

    @Test func limiterCapsConcurrentWork() async {
        let limiter = AsyncLimiter(limit: 3)
        let counter = PeakCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await limiter.acquire()
                    await counter.enter()
                    try? await Task.sleep(for: .milliseconds(10))
                    await counter.leave()
                    await limiter.release()
                }
            }
        }
        #expect(await counter.peak == 3)
        #expect(await counter.current == 0)
    }

    // MARK: - Helpers

    private func age(_ key: String, by seconds: TimeInterval) throws {
        let url = directory.appendingPathComponent(key)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)],
                                              ofItemAtPath: url.path)
    }

    private func writeImage(width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = directory.appendingPathComponent("photo.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixelSize(of png: Data) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }
}

private actor PeakCounter {
    private(set) var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}
