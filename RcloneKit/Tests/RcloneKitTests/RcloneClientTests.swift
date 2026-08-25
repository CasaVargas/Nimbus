import Foundation
import Testing
@testable import RcloneKit

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponses: [String: (Data, Int)] = [:]

    /// Last request URL seen per endpoint path, so tests can assert on
    /// query parameters (rclone reads uploadfile's fs/remote from the
    /// query only — a contract worth pinning).
    nonisolated(unsafe) static var lastRequestURLs: [String: URL] = [:]
    nonisolated(unsafe) static var lastRequestBodies: [String: Data] = [:]

    static func register(endpoint: String, json: String, status: Int = 200) {
        mockResponses[endpoint] = (json.data(using: .utf8)!, status)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        Self.lastRequestURLs[path] = url
        Self.lastRequestBodies[path] = request.httpBody ?? readBody(from: request.httpBodyStream)
        if let (data, status) = Self.mockResponses[path] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// Register all mocks once at module load so parallel tests don't race
private let _setupMocks: Void = {
    // rc
    MockURLProtocol.register(endpoint: "rc/noop", json: "{}")

    // config
    MockURLProtocol.register(endpoint: "config/listremotes", json: #"{"remotes": ["gdrive", "s3", "dropbox"]}"#)
    MockURLProtocol.register(endpoint: "config/dump", json: #"{"gdrive": {"type": "drive", "token": "abc"}, "s3": {"type": "s3", "region": "us-east-1"}}"#)
    MockURLProtocol.register(endpoint: "config/providers", json: #"{"providers": [{"Name": "s3", "Description": "Amazon S3", "Prefix": "s3", "Options": []}]}"#)
    MockURLProtocol.register(endpoint: "config/create", json: "{}")
    MockURLProtocol.register(endpoint: "config/delete", json: "{}")
    MockURLProtocol.register(endpoint: "options/set", json: "{}")

    // operations
    MockURLProtocol.register(endpoint: "operations/list", json: #"""
    {
        "list": [
            {
                "Path": "photo.jpg",
                "Name": "photo.jpg",
                "Size": 2048,
                "MimeType": "image/jpeg",
                "ModTime": "2026-03-31T10:00:00Z",
                "IsDir": false
            },
            {
                "Path": "docs",
                "Name": "docs",
                "Size": -1,
                "MimeType": "inode/directory",
                "ModTime": "2026-03-31T09:00:00Z",
                "IsDir": true
            }
        ]
    }
    """#)
    MockURLProtocol.register(endpoint: "operations/mkdir", json: "{}")
    MockURLProtocol.register(endpoint: "operations/deletefile", json: "{}")
    MockURLProtocol.register(endpoint: "operations/purge", json: "{}")
    MockURLProtocol.register(endpoint: "operations/movefile", json: "{}")
    MockURLProtocol.register(endpoint: "operations/uploadfile", json: "{}")
    // Downloads are GET /[fs]/path via --rc-serve (operations/cat does not
    // exist in rclone's RC API). MockURLProtocol keys on the percent-decoded
    // URL path, so this registration pins the download URL shape: a client
    // regression to any other endpoint 404s the mock and fails the test.
    MockURLProtocol.register(endpoint: "[gdrive:]/photo.jpg", json: "hello world")
    MockURLProtocol.register(endpoint: "operations/about", json: #"{"total": 1000000, "used": 500000, "free": 500000}"#)
    MockURLProtocol.register(endpoint: "operations/stat", json: #"""
    {
        "item": {
            "Path": "photo.jpg",
            "Name": "photo.jpg",
            "Size": 2048,
            "MimeType": "image/jpeg",
            "ModTime": "2026-03-31T10:00:00Z",
            "IsDir": false
        }
    }
    """#)

    // sync
    MockURLProtocol.register(endpoint: "sync/move", json: "{}")

    // error test endpoint
    MockURLProtocol.register(
        endpoint: "test/error-endpoint",
        json: #"{"error": "directory not found", "path": "test/error-endpoint", "status": 404}"#,
        status: 404
    )
    MockURLProtocol.register(
        endpoint: "test/error-body-200",
        json: #"{"error": "options rejected", "path": "options/set", "status": 500}"#
    )
}()

func makeTestClient() -> RcloneClient {
    _ = _setupMocks
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return RcloneClient(port: 5572, session: session)
}

// MARK: - Client Tests

@Test func healthCheckSuccess() async throws {
    let client = makeTestClient()
    let healthy = await client.healthCheck()
    #expect(healthy == true)
}

@Test func healthCheckFailure() async throws {
    // Port 9999 — rc/noop is registered but the URL won't match since port differs
    // Actually MockURLProtocol ignores port, so use an unregistered endpoint approach:
    // The mock for rc/noop returns 200, so health check will pass.
    // For failure, we need a client that doesn't use MockURLProtocol at all.
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 1
    // No mock protocol registered — real network call to localhost:9999 will fail
    let session = URLSession(configuration: config)
    let client = RcloneClient(port: 9999, session: session)
    let healthy = await client.healthCheck()
    #expect(healthy == false)
}

@Test func callDecodesResponse() async throws {
    let client = makeTestClient()
    let response: RemoteListResponse = try await client.call("config/listremotes")
    #expect(response.remotes.count >= 2) // At least gdrive and s3
}

@Test func callWithParams() async throws {
    let client = makeTestClient()
    // operations/list returns 2 items (set up in _setupMocks)
    let response: ListResponse = try await client.call("operations/list", params: [
        "fs": "gdrive:",
        "remote": "documents",
    ])
    #expect(response.list.count == 2)
}

@Test func setConcurrentTransfersUsesTypedOptionsSetPayload() async throws {
    let client = makeTestClient()

    try await client.setConcurrentTransfers(7)

    let body = try #require(MockURLProtocol.lastRequestBodies["options/set"])
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let main = try #require(json?["main"] as? [String: Int])
    #expect(main["Transfers"] == 7)
}

@Test func callThrowsOnErrorStatus() async throws {
    let client = makeTestClient()
    do {
        let _: ListResponse = try await client.call("test/error-endpoint")
        #expect(Bool(false), "Should have thrown")
    } catch let error as RcloneError {
        if case .requestFailed(let status, let message) = error {
            #expect(status == 404)
            #expect(message.contains("directory not found"))
        } else {
            #expect(Bool(false), "Wrong error case: \(error)")
        }
    }
}

@Test func callThrowsOnEmbeddedErrorBodyEvenWithSuccessfulStatus() async throws {
    let client = makeTestClient()
    do {
        let _: ListResponse = try await client.call("test/error-body-200")
        #expect(Bool(false), "Should have thrown")
    } catch let error as RcloneError {
        if case .requestFailed(let status, let message) = error {
            #expect(status == 500)
            #expect(message == "options rejected")
        } else {
            #expect(Bool(false), "Wrong error case: \(error)")
        }
    }
}
