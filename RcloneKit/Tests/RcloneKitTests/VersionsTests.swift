import Foundation
import Testing
@testable import RcloneKit

/// Scripted daemon for version tests only, apart from `MockURLProtocol` so
/// the shared `operations/list` / `operations/copyfile` mocks stay untouched.
private final class VersionsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String: [Data]] = [:]

    static func reset() { lock.withLock { bodies = [:] } }

    static func lastBody(for endpoint: String) -> [String: Any]? {
        lock.withLock { bodies[endpoint]?.last }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let endpoint = String(request.url!.path.dropFirst())
        let body = Self.readBody(request)
        Self.lock.withLock { Self.bodies[endpoint, default: []].append(body) }
        let reply = switch endpoint {
        case "operations/list": versionsListing
        case "operations/copyfile": #"{"jobid": 7}"#
        default: "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeVersionsClient() -> RcloneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VersionsURLProtocol.self]
    return RcloneClient(port: 5572, session: URLSession(configuration: config))
}

/// Shape captured from rclone 1.76 `operations/list` on `remote,versions:`.
private let versionsListing = #"""
{"list": [
  {"Path": "bkt/docs/noext", "Name": "noext", "Size": 2, "MimeType": "application/octet-stream", "ModTime": "2026-11-11T14:09:51.226544605-05:00", "IsDir": false},
  {"Path": "bkt/docs/report-v2026-11-11-190948-000.txt", "Name": "report-v2026-11-11-190948-000.txt", "Size": 4, "MimeType": "text/plain", "ModTime": "2026-11-11T14:09:48.635906550-05:00", "IsDir": false},
  {"Path": "bkt/docs/report-v2026-11-11-190951-250.txt", "Name": "report-v2026-11-11-190951-250.txt", "Size": 14, "MimeType": "text/plain", "ModTime": "2026-11-11T14:09:51.171616171-05:00", "IsDir": false},
  {"Path": "bkt/docs/report-v2026-11-11-190949-000.txt", "Name": "report-v2026-11-11-190949-000.txt", "Size": 8, "MimeType": "text/plain", "ModTime": "2026-11-11T14:09:49.915222023-05:00", "IsDir": false},
  {"Path": "bkt/docs/report.txt", "Name": "report.txt", "Size": 4, "MimeType": "text/plain", "ModTime": "2026-11-11T14:09:48.635906550-05:00", "IsDir": false},
  {"Path": "bkt/docs/report-v2026-11-11-190950-000", "Name": "report-v2026-11-11-190950-000", "Size": 1, "MimeType": "inode/directory", "ModTime": "2026-11-11T14:09:48Z", "IsDir": true}
]}
"""#

private func utc(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: text)!
}

@Suite("Service versions", .serialized)
struct VersionsTests {
    @Test(arguments: [
        ("r:", "r,versions:"),
        ("my cloud:", "my cloud,versions:"),
        ("r:bucket/dir", "r,versions:bucket/dir"),
        ("r,region=eu:", "r,region=eu,versions:"),
    ])
    func versionsFsAddsTheOption(fs: String, expected: String) {
        #expect(RcloneClient.versionsFs(fs) == expected)
    }

    @Test func parsesRcloneVersionNames() {
        #expect(FileVersion.savedAt(name: "report-v2026-11-11-190948-120.txt", file: "report.txt")
                == utc("2026-11-11T19:09:48.120Z"))
        #expect(FileVersion.savedAt(name: "noext-v2026-01-02-030405-000", file: "noext")
                == utc("2026-01-02T03:04:05.000Z"))
        // Go's path.Ext: only the last extension, and a dot file is all extension.
        #expect(FileVersion.savedAt(name: "a.tar-v2026-01-02-030405-000.gz", file: "a.tar.gz") != nil)
        #expect(FileVersion.savedAt(name: "-v2026-01-02-030405-000.env", file: ".env") != nil)
    }

    @Test func rejectsOtherNames() {
        #expect(FileVersion.savedAt(name: "report.txt", file: "report.txt") == nil)
        #expect(FileVersion.savedAt(name: "report-v2026-11-11-190948-000.txt", file: "report.md") == nil)
        #expect(FileVersion.savedAt(name: "report2-v2026-11-11-190948-000.txt", file: "report.txt") == nil)
        #expect(FileVersion.savedAt(name: "report-v2026-11-11-190948.txt", file: "report.txt") == nil)
        #expect(FileVersion.savedAt(name: "report-v2026-13-45-990948-000.txt", file: "report.txt") == nil)
    }

    @Test func listsTheFilesVersionsNewestFirst() async throws {
        VersionsURLProtocol.reset()
        let versions = try await makeVersionsClient().fileVersions(fs: "mini:", remote: "bkt/docs/report.txt")

        let body = try #require(VersionsURLProtocol.lastBody(for: "operations/list"))
        #expect(body["fs"] as? String == "mini,versions:")
        #expect(body["remote"] as? String == "bkt/docs")

        #expect(versions.map(\.path) == [
            "bkt/docs/report-v2026-11-11-190951-250.txt",
            "bkt/docs/report-v2026-11-11-190949-000.txt",
            "bkt/docs/report-v2026-11-11-190948-000.txt",
        ])
        #expect(versions.map(\.size) == [14, 8, 4])
        #expect(versions.first?.savedAt == utc("2026-11-11T19:09:51.250Z"))
    }

    @Test func fileAtTheRootListsTheRoot() async throws {
        VersionsURLProtocol.reset()
        _ = try await makeVersionsClient().fileVersions(fs: "b2:", remote: "report.txt")
        let body = try #require(VersionsURLProtocol.lastBody(for: "operations/list"))
        #expect(body["remote"] as? String == "")
    }

    @Test func restoreCopiesTheVersionOverTheLivePath() async throws {
        VersionsURLProtocol.reset()
        let version = FileVersion(path: "bkt/docs/report-v2026-11-11-190948-000.txt",
                                  name: "report-v2026-11-11-190948-000.txt",
                                  savedAt: utc("2026-11-11T19:09:48.000Z"), size: 4)
        let job = try await makeVersionsClient().copyVersionAsync(
            fs: "mini:", version: version, dstFs: "mini:", dstRemote: "bkt/docs/report.txt")

        #expect(job == 7)
        let body = try #require(VersionsURLProtocol.lastBody(for: "operations/copyfile"))
        #expect(body["srcFs"] as? String == "mini,versions:")
        #expect(body["srcRemote"] as? String == "bkt/docs/report-v2026-11-11-190948-000.txt")
        #expect(body["dstFs"] as? String == "mini:")
        #expect(body["dstRemote"] as? String == "bkt/docs/report.txt")
        #expect(body["_async"] as? Bool == true)
    }
}
