import Foundation
import Testing
@testable import RcloneKit

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponses: [String: (Data, Int)] = [:]

    /// Last request URL seen per endpoint path, so tests can assert on
    /// query parameters (rclone reads uploadfile's fs/remote from the
    /// query only — a contract worth pinning).
    nonisolated(unsafe) static var lastRequestURLs: [String: URL] = [:]

    static func register(endpoint: String, json: String, status: Int = 200) {
        mockResponses[endpoint] = (json.data(using: .utf8)!, status)
    }

    /// FIFO queues per endpoint, checked before `mockResponses`. Lets one
    /// test script a *sequence* of replies from a single endpoint — required
    /// for config/create, which returns a different question each call.
    nonisolated(unsafe) static var responseQueues: [String: [(Data, Int)]] = [:]

    /// Last request body seen per endpoint path. URLProtocol nils out
    /// `request.httpBody` for POSTs, so this is read from `httpBodyStream`.
    nonisolated(unsafe) static var lastRequestBodies: [String: Data] = [:]

    static func enqueue(endpoint: String, json: String, status: Int = 200) {
        responseQueues[endpoint, default: []].append((json.data(using: .utf8)!, status))
    }

    /// Clears queued responses and the captured body for ONE endpoint.
    ///
    /// Deliberately NOT global. `.serialized` orders tests within a single
    /// suite; two different `.serialized` suites still run concurrently with
    /// each other, so a global clear lets one suite wipe another suite's
    /// queued responses mid-test. Scope every reset to the endpoint the
    /// calling test actually owns.
    static func reset(endpoint: String) {
        responseQueues[endpoint] = nil
        lastRequestBodies[endpoint] = nil
    }

    /// URLProtocol hands POST bodies over as a stream, not `httpBody`.
    private static func readBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
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
        if let body = Self.readBody(request) { Self.lastRequestBodies[path] = body }

        let queued: (Data, Int)? = {
            guard var queue = Self.responseQueues[path], !queue.isEmpty else { return nil }
            let head = queue.removeFirst()
            Self.responseQueues[path] = queue
            return head
        }()

        if let (data, status) = queued ?? Self.mockResponses[path] {
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

    // Dedicated endpoint for mockCapturesRequestBody — config/create is also
    // hit by RemotesTests.swift's bare createRemote() test, which would race
    // with lastRequestBodies["config/create"] if this test asserted on that
    // shared path instead.
    MockURLProtocol.register(endpoint: "test/body-capture", json: "{}")
}()

func makeTestClient() -> RcloneClient {
    _ = _setupMocks
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return RcloneClient(port: 5572, session: session)
}

// MARK: - Client Tests

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

// MARK: - Mock Harness Tests
//
// Serialized: MockURLProtocol.responseQueues / lastRequestBodies are shared
// statics keyed by endpoint path. Swift Testing runs non-serialized
// free-function tests in parallel, so two tests hitting the same endpoint
// (e.g. config/create) can overwrite each other's queued/captured state.
// `.serialized` is a suite trait, so these live in a dedicated suite rather
// than as bare @Test free functions.
//
// healthCheckSuccess() lives here too, not in "Client Tests" above: it also
// resolves against "rc/noop" through the same mock, so as a bare free
// function it can run concurrently with mockQueueReturnsResponsesInOrder and
// silently dequeue one of that test's queued responses (confirmed by
// repeated runs of the full suite — deterministic, not a rare flake).
// Moving it into this serialized suite removes the race without touching
// its body.
@Suite("MockHarness", .serialized)
struct MockHarnessTests {
    @Test func healthCheckSuccess() async throws {
        let client = makeTestClient()
        let healthy = await client.healthCheck()
        #expect(healthy == true)
    }

    @Test func mockQueueReturnsResponsesInOrder() async throws {
        MockURLProtocol.reset(endpoint: "rc/noop")
        MockURLProtocol.enqueue(endpoint: "rc/noop", json: #"{"n": 1}"#)
        MockURLProtocol.enqueue(endpoint: "rc/noop", json: #"{"n": 2}"#)

        struct Counted: Decodable, Sendable { let n: Int }
        let client = makeTestClient()

        let first: Counted = try await client.call("rc/noop")
        let second: Counted = try await client.call("rc/noop")
        #expect(first.n == 1)
        #expect(second.n == 2)

        // Queue exhausted → falls back to the static registration.
        let third: [String: String] = try await client.call("rc/noop")
        #expect(third.isEmpty)
    }

    @Test func mockCapturesRequestBody() async throws {
        MockURLProtocol.reset(endpoint: "test/body-capture")
        let client = makeTestClient()
        // A dedicated endpoint no other test touches: the point of this test is
        // that lastRequestBodies captures a POST body off httpBodyStream, which
        // must not depend on another test's traffic to a shared path.
        let _: [String: String] = try await client.call(
            "test/body-capture",
            params: ["name": "bodytest", "type": "s3"]
        )

        let body = try #require(MockURLProtocol.lastRequestBodies["test/body-capture"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "bodytest")
        #expect(json["type"] as? String == "s3")
    }
}
