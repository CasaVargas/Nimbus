import CoreGraphics
import Foundation
import ImageIO
import RcloneKit
import Testing
import UniformTypeIdentifiers

@testable import Nimbus

@Suite("BrowserThumbnailLoader")
struct BrowserThumbnailLoaderTests {
    private func request(
        _ name: String = "photo.png", size: Int64 = 4096,
        modTime: Date? = Date(timeIntervalSince1970: 1_000), maxPixel: Int = 144
    ) -> ThumbnailRequest {
        ThumbnailRequest(remote: "drive", path: "Photos/\(name)", name: name, size: size,
                         modTime: modTime, maxPixel: maxPixel)
    }

    private func scratchCache() -> ThumbnailCache {
        ThumbnailCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-thumb-tests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func skipsFilesThePolicyRejects() async {
        let client = FakeDownloadClient(payload: Self.pngData(width: 400, height: 200))
        let loader = BrowserThumbnailLoader(client: client, cache: nil)

        #expect(await loader.image(for: request(size: 30 * 1024 * 1024)) == nil)
        #expect(await loader.image(for: request("notes.txt")) == nil)
        #expect(await loader.image(for: request(size: -1)) == nil)
        #expect(await loader.image(for: request("no-extension")) == nil)
        #expect(client.downloads == 0)
    }

    @Test func drawsAndCachesAPhoto() async throws {
        let client = FakeDownloadClient(payload: Self.pngData(width: 400, height: 200))
        let cache = scratchCache()
        let loader = BrowserThumbnailLoader(client: client, cache: cache)

        let image = try #require(await loader.image(for: request()))
        #expect(max(image.width, image.height) <= 144)
        #expect(image.width == 2 * image.height)
        #expect(client.downloads == 1)
        #expect(loader.cachedImage(for: request()) != nil)

        // Memory hit.
        _ = await loader.image(for: request())
        #expect(client.downloads == 1)

        // A new loader (next launch) reads the disk cache instead.
        let relaunched = BrowserThumbnailLoader(client: client, cache: cache)
        #expect(relaunched.cachedImage(for: request()) == nil)
        #expect(await relaunched.image(for: request()) != nil)
        #expect(client.downloads == 1)
    }

    @Test func changedSizeOrDateMissesTheCache() async {
        let client = FakeDownloadClient(payload: Self.pngData(width: 400, height: 200))
        let loader = BrowserThumbnailLoader(client: client, cache: scratchCache())

        _ = await loader.image(for: request())
        _ = await loader.image(for: request(size: 5000))
        _ = await loader.image(for: request(modTime: Date(timeIntervalSince1970: 2_000)))
        #expect(client.downloads == 3)
    }

    @Test func removesTheTempFile() async throws {
        let client = FakeDownloadClient(payload: Self.pngData(width: 400, height: 200))
        let loader = BrowserThumbnailLoader(client: client, cache: nil)

        _ = await loader.image(for: request())
        let directory = try #require(client.lastURL).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func failedDownloadReturnsNil() async {
        let client = FakeDownloadClient(payload: nil)
        let loader = BrowserThumbnailLoader(client: client, cache: nil)

        #expect(await loader.image(for: request()) == nil)
        #expect(client.downloads == 1)
    }

    @Test func undecodableBytesReturnNil() async throws {
        let client = FakeDownloadClient(payload: Data("not a picture".utf8))
        let loader = BrowserThumbnailLoader(client: client, cache: scratchCache())

        #expect(await loader.image(for: request()) == nil)
        #expect(loader.cachedImage(for: request()) == nil)
        let directory = try #require(client.lastURL).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func cancelledBeforeItsTurnDoesNotDownload() async {
        let client = FakeDownloadClient(payload: Self.pngData(width: 400, height: 200))
        let limiter = AsyncLimiter(limit: 1)
        let loader = BrowserThumbnailLoader(client: client, cache: nil, limiter: limiter)
        let request = request()

        await limiter.acquire() // every slot busy
        let waiting = Task { await loader.image(for: request) }
        try? await Task.sleep(for: .milliseconds(50))
        waiting.cancel()
        await limiter.release()

        #expect(await waiting.value == nil)
        #expect(client.downloads == 0)

        // The slot was handed back: the next request goes through.
        #expect(await loader.image(for: request) != nil)
    }

    @Test func requestFromAFileItemUsesTheFullPathAndSkipsFolders() {
        let file = FileItem(path: "a.png", name: "a.png", size: 10, mimeType: "image/png", modTime: nil,
                            isDir: false, fileID: "id-1", qualifiedRemotePath: "drive:Photos/2026/a.png")
        let fromFile = ThumbnailRequest(file: file, remote: "drive", maxPixel: 144)
        #expect(fromFile.path == "Photos/2026/a.png")
        #expect(fromFile.kind == .image)

        let folder = FileItem(path: "scans.pdf", name: "scans.pdf", size: 10, mimeType: "inode/directory",
                              modTime: nil, isDir: true, fileID: nil, qualifiedRemotePath: "drive:scans.pdf")
        #expect(ThumbnailRequest(file: folder, remote: "drive", maxPixel: 144).kind == nil)
    }

    static func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

/// Writes `payload` to a temp file the way `downloadToTemp` does; throws
/// when there's none.
private final class FakeDownloadClient: RcloneClientProtocol, @unchecked Sendable {
    private let payload: Data?
    private let lock = NSLock()
    private var _downloads = 0
    private var _lastURL: URL?

    init(payload: Data?) {
        self.payload = payload
    }

    var downloads: Int { lock.withLock { _downloads } }
    var lastURL: URL? { lock.withLock { _lastURL } }

    func downloadToTemp(remote _: String, path: String) async throws -> URL {
        lock.withLock { _downloads += 1 }
        guard let payload else { throw CocoaError(.fileReadUnknown) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-thumb-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent((path as NSString).lastPathComponent)
        try payload.write(to: url)
        lock.withLock { _lastURL = url }
        return url
    }
}
