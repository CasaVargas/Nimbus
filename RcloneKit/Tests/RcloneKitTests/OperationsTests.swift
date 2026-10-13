import Foundation
import Testing
@testable import RcloneKit

private final class UploadCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func listFiles() async throws {
    let client = makeTestClient()
    let files = try await client.listFiles(fs: "gdrive:", remote: "")
    #expect(files.count == 2)
    #expect(files[0].name == "photo.jpg")
    #expect(files[1].isDir == true)
}

@Test func mkdir() async throws {
    let client = makeTestClient()
    try await client.mkdir(fs: "gdrive:", remote: "new-folder")
}

@Test func deleteFile() async throws {
    let client = makeTestClient()
    try await client.deleteFile(fs: "gdrive:", remote: "old-file.txt")
}

@Test func about() async throws {
    let client = makeTestClient()
    let info = try await client.about(fs: "gdrive:")
    #expect(info.total == 1_000_000)
    #expect(info.used == 500_000)
}

@Test func purge() async throws {
    let client = makeTestClient()
    try await client.purge(fs: "gdrive:", remote: "old-folder")
}

@Test func moveFile() async throws {
    let client = makeTestClient()
    try await client.moveFile(srcFs: "gdrive:", srcRemote: "a.txt", dstFs: "gdrive:", dstRemote: "b.txt")
}

@Test func moveDirectory() async throws {
    let client = makeTestClient()
    try await client.moveDirectory(srcFs: "gdrive:old-dir", dstFs: "gdrive:new-dir")
}

@Test func stat() async throws {
    let client = makeTestClient()
    let item = try await client.stat(fs: "gdrive:", remote: "photo.jpg")
    #expect(item.name == "photo.jpg")
    #expect(item.isDir == false)
}

@Test func downloadFileWritesDestination() async throws {
    let client = makeTestClient()
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dest) }
    try await client.downloadFile(fs: "gdrive:", remote: "photo.jpg", to: dest)
    let data = try Data(contentsOf: dest)
    #expect(!data.isEmpty)
}

@Test func uploadFileUsesExplicitFilenameOverride() async throws {
    let client = makeTestClient()
    let src = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "hello".write(to: src, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: src) }
    // The staged local file's name deliberately doesn't match the desired
    // remote filename — `filename:` must win.
    try await client.uploadFile(from: src, fs: "gdrive:", remote: "docs", filename: "renamed.txt")
}

@Test func uploadFileDefaultsFilenameToLocalBasename() async throws {
    let client = makeTestClient()
    let src = FileManager.default.temporaryDirectory.appendingPathComponent("report.txt")
    try "hello".write(to: src, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: src) }
    try await client.uploadFile(from: src, fs: "gdrive:", remote: "docs")
}

@Test func uploadFileSendsFsAndRemoteAsQueryParameters() async throws {
    // rclone's operations/uploadfile reads fs/remote from the URL query
    // ONLY; passing them as multipart form fields returns 400. Pin the
    // query contract so a refactor can't silently regress uploads.
    UploadCaptureURLProtocol.capturedRequest = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UploadCaptureURLProtocol.self]
    let session = URLSession(configuration: config)
    let client = RcloneClient(port: 5572, session: session)
    let src = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "hello".write(to: src, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: src) }
    try await client.uploadFile(from: src, fs: "gdrive:", remote: "docs/sub dir")

    let url = try #require(UploadCaptureURLProtocol.capturedRequest?.url)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.contains(URLQueryItem(name: "fs", value: "gdrive:")))
    #expect(items.contains(URLQueryItem(name: "remote", value: "docs/sub dir")))
}
