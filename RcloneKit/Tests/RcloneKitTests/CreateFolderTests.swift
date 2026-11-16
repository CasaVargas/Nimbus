import Foundation
import Testing
@testable import RcloneKit

/// Records every request in order and answers each endpoint with canned
/// JSON: one answer per call, the last one repeating. Its own session, so it shares no state with `MockURLProtocol`.
private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded {
        let endpoint: String
        let query: [URLQueryItem]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedRequests: [Recorded] = []
    nonisolated(unsafe) private static var storedResponses: [String: [String]] = [:]

    static var requests: [Recorded] { lock.withLock { storedRequests } }

    static func start(responses: [String: [String]]) {
        lock.withLock {
            storedRequests = []
            storedResponses = responses
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://127.0.0.1")!
        let endpoint = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let json = Self.lock.withLock {
            Self.storedRequests.append(Recorded(endpoint: endpoint, query: query, body: body))
            guard var queue = Self.storedResponses[endpoint], let next = queue.first else { return "{}" }
            if queue.count > 1 {
                queue.removeFirst()
                Self.storedResponses[endpoint] = queue
            }
            return next
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Issue #139: bucket stores keep no empty folders, so `operations/mkdir`
/// inside a bucket succeeds and creates nothing.
@Suite("Create folder", .serialized)
struct CreateFolderTests {
    private static let noEmptyFolders = #"{"Features": {"CanHaveEmptyDirectories": false}}"#
    private static let missing = #"{"item": null}"#
    private static let found = #"{"item": {"Path": "New", "Name": "New", "Size": -1, "MimeType": "inode/directory", "ModTime": "2000-01-01T00:00:00Z", "IsDir": true}}"#

    /// A client whose remote keeps no empty folders and whose new folder
    /// is missing after `mkdir`, unless `responses` says otherwise.
    private func client(config: [String], responses: [String: [String]] = [:]) -> RcloneClient {
        var all: [String: [String]] = [
            "operations/fsinfo": [Self.noEmptyFolders],
            "operations/stat": [Self.missing],
            "config/get": config,
        ]
        all.merge(responses) { _, new in new }
        RecordingURLProtocol.start(responses: all)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    private var endpoints: [String] { RecordingURLProtocol.requests.map(\.endpoint) }

    private func json(_ recorded: RecordingURLProtocol.Recorded) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
    }

    @Test func servicesWithRealFoldersOnlyMkdir() async throws {
        let client = client(config: [#"{"type": "drive"}"#], responses: [
            "operations/fsinfo": [#"{"Features": {"CanHaveEmptyDirectories": true}}"#],
        ])
        try await client.createFolder(fs: "gdrive:", remote: "Docs/New")
        #expect(endpoints == ["operations/mkdir", "operations/fsinfo"])
    }

    @Test func b2FolderGetsBackblazePlaceholder() async throws {
        let client = client(config: [#"{"type": "b2"}"#])
        try await client.createFolder(fs: "BackBlaze:", remote: "my-bucket/Photos/2026")

        #expect(endpoints == ["operations/mkdir", "operations/fsinfo", "operations/stat",
                              "config/get", "operations/uploadfile"])
        let requests = RecordingURLProtocol.requests
        let upload = try #require(requests.last)
        #expect(upload.query.contains(URLQueryItem(name: "fs", value: "BackBlaze:")))
        #expect(upload.query.contains(URLQueryItem(name: "remote", value: "my-bucket/Photos/2026")))
        let body = String(decoding: upload.body, as: UTF8.self)
        #expect(body.contains(#"filename=".bzEmpty""#))
        // Zero bytes between the part's headers and the closing boundary.
        #expect(body.contains("\r\n\r\n\r\n--"))
        #expect(try json(requests[3])["name"] as? String == "BackBlaze")
    }

    @Test func aNewBucketNeedsNothingMore() async throws {
        let client = client(config: [#"{"type": "b2"}"#], responses: [
            "operations/stat": [#"{"item": {"Path": "new-bucket", "Name": "new-bucket", "Size": -1, "MimeType": "inode/directory", "ModTime": "2000-01-01T00:00:00Z", "IsDir": true}}"#],
        ])
        try await client.createFolder(fs: "BackBlaze:", remote: "new-bucket")
        #expect(endpoints == ["operations/mkdir", "operations/fsinfo", "operations/stat"])
    }

    @Test func s3TurnsOnDirectoryMarkersAndRepeatsMkdir() async throws {
        let client = client(config: [#"{"type": "s3", "provider": "AWS"}"#], responses: [
            "operations/stat": [Self.missing, Self.found],
        ])
        try await client.createFolder(fs: "aws:", remote: "bucket/New")

        #expect(endpoints == ["operations/mkdir", "operations/fsinfo", "operations/stat", "config/get",
                              "config/update", "fscache/clear", "operations/mkdir", "operations/stat"])
        let update = try json(RecordingURLProtocol.requests[4])
        #expect(update["name"] as? String == "aws")
        #expect((update["parameters"] as? [String: Any])?["directory_markers"] as? String == "true")
    }

    @Test func cryptOverS3TurnsMarkersOnForTheS3Remote() async throws {
        let client = client(config: [
            #"{"type": "crypt", "remote": "aws:bucket/secret"}"#,
            #"{"type": "s3"}"#,
        ], responses: ["operations/stat": [Self.missing, Self.found]])
        try await client.createFolder(fs: "vault:", remote: "New")

        #expect(endpoints == ["operations/mkdir", "operations/fsinfo", "operations/stat", "config/get", "config/get",
                              "config/update", "fscache/clear", "operations/mkdir", "operations/stat"])
        let requests = RecordingURLProtocol.requests
        #expect(try json(requests[3])["name"] as? String == "vault")
        #expect(try json(requests[4])["name"] as? String == "aws")
        #expect(try json(requests[5])["name"] as? String == "aws")
        #expect(try json(requests[7])["fs"] as? String == "vault:")
    }

    @Test func markersThatLeaveNoFolderFallBackToAPlaceholder() async throws {
        let client = client(config: [#"{"type": "s3"}"#])
        try await client.createFolder(fs: "aws:", remote: "bucket/New")
        let upload = try #require(RecordingURLProtocol.requests.last)
        #expect(upload.endpoint == "operations/uploadfile")
        #expect(String(decoding: upload.body, as: UTF8.self).contains(#"filename=".keep""#))
    }

    @Test func aliasOverB2StillGetsBackblazePlaceholder() async throws {
        let client = client(config: [
            #"{"type": "alias", "remote": "BackBlaze:my-bucket/Docs"}"#,
            #"{"type": "b2"}"#,
        ])
        try await client.createFolder(fs: "docs:", remote: "New")
        let upload = try #require(RecordingURLProtocol.requests.last)
        #expect(upload.endpoint == "operations/uploadfile")
        #expect(upload.query.contains(URLQueryItem(name: "fs", value: "docs:")))
        #expect(String(decoding: upload.body, as: UTF8.self).contains(#"filename=".bzEmpty""#))
    }

    @Test func otherBucketStoresGetAKeepFile() async throws {
        let client = client(config: [#"{"type": "swift"}"#])
        try await client.createFolder(fs: "ovh:", remote: "container/New")
        let upload = try #require(RecordingURLProtocol.requests.last)
        #expect(upload.endpoint == "operations/uploadfile")
        #expect(String(decoding: upload.body, as: UTF8.self).contains(#"filename=".keep""#))
    }
}
