import Foundation
import Testing
@testable import RcloneKit

/// Records every request in order and answers each endpoint with canned
/// JSON. Its own session, so it shares no state with `MockURLProtocol`.
private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded {
        let endpoint: String
        let query: [URLQueryItem]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedRequests: [Recorded] = []
    nonisolated(unsafe) private static var storedResponses: [String: String] = [:]

    static var requests: [Recorded] { lock.withLock { storedRequests } }

    static func start(responses: [String: String]) {
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
            return Self.storedResponses[endpoint] ?? "{}"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Issue #139: Backblaze B2 keeps no empty folders, so `operations/mkdir`
/// inside a bucket succeeds and creates nothing.
@Suite("Create folder", .serialized)
struct CreateFolderTests {
    private func client(remoteType: String) -> RcloneClient {
        RecordingURLProtocol.start(responses: ["config/get": #"{"type": "\#(remoteType)"}"#])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    @Test func b2FolderGetsBackblazePlaceholder() async throws {
        let client = client(remoteType: "b2")
        try await client.createFolder(fs: "BackBlaze:", remote: "my-bucket/Photos/2026")

        let requests = RecordingURLProtocol.requests
        #expect(requests.map(\.endpoint) == ["operations/mkdir", "config/get", "operations/uploadfile"])
        let upload = try #require(requests.last)
        #expect(upload.query.contains(URLQueryItem(name: "fs", value: "BackBlaze:")))
        #expect(upload.query.contains(URLQueryItem(name: "remote", value: "my-bucket/Photos/2026")))
        let body = String(decoding: upload.body, as: UTF8.self)
        #expect(body.contains(#"filename=".bzEmpty""#))
        // Zero bytes between the part's headers and the closing boundary.
        #expect(body.contains("\r\n\r\n\r\n--"))
        let lookup = try #require(try JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
        #expect(lookup["name"] as? String == "BackBlaze")
    }

    @Test func b2BucketItselfGetsNoPlaceholder() async throws {
        let client = client(remoteType: "b2")
        try await client.createFolder(fs: "BackBlaze:", remote: "new-bucket")
        #expect(RecordingURLProtocol.requests.map(\.endpoint) == ["operations/mkdir"])
    }

    @Test func otherServicesOnlyMkdir() async throws {
        let client = client(remoteType: "drive")
        try await client.createFolder(fs: "gdrive:", remote: "Docs/New")
        #expect(RecordingURLProtocol.requests.map(\.endpoint) == ["operations/mkdir", "config/get"])
    }

    @Test func folderUnderAB2SubpathFsGetsPlaceholder() async throws {
        let client = client(remoteType: "b2")
        try await client.createFolder(fs: "BackBlaze:my-bucket", remote: "New")
        #expect(RecordingURLProtocol.requests.map(\.endpoint)
            == ["operations/mkdir", "config/get", "operations/uploadfile"])
    }
}
