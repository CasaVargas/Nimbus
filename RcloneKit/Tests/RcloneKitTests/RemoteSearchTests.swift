import Foundation
import Testing
@testable import RcloneKit

/// Scripted daemon for search tests only. Kept apart from `MockURLProtocol`
/// so concurrently running suites can't pop each other's `job/status` replies.
private final class SearchURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statusReplies: [String] = []
    nonisolated(unsafe) private static var bodies: [String: [Data]] = [:]
    /// When set, `job/status` keeps answering "not finished".
    nonisolated(unsafe) static var neverFinish = false

    static func reset(statusReplies replies: [String], neverFinish: Bool = false) {
        lock.withLock {
            statusReplies = replies
            bodies = [:]
            self.neverFinish = neverFinish
        }
    }

    static func bodies(for endpoint: String) -> [[String: Any]] {
        lock.withLock { bodies[endpoint] ?? [] }
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
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
        let reply: String = Self.lock.withLock {
            Self.bodies[endpoint, default: []].append(body)
            switch endpoint {
            case "operations/list":
                return #"{"jobid": 42}"#
            case "job/status":
                if Self.neverFinish { return #"{"finished": false}"# }
                return Self.statusReplies.isEmpty ? #"{"finished": false}"# : Self.statusReplies.removeFirst()
            default:
                return "{}"
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSearchClient() -> RcloneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SearchURLProtocol.self]
    return RcloneClient(port: 5572, session: URLSession(configuration: config))
}

private let finishedListing = #"""
{"finished": true, "success": true, "error": "", "output": {"list": [
  {"Path": "Report.pdf", "Name": "Report.pdf", "Size": 10, "MimeType": "application/pdf", "ModTime": "2026-11-11T09:59:48Z", "IsDir": false},
  {"Path": "a", "Name": "a", "Size": 0, "MimeType": "inode/directory", "ModTime": "2026-11-11T09:59:48Z", "IsDir": true},
  {"Path": "a/Reports", "Name": "Reports", "Size": 0, "MimeType": "inode/directory", "ModTime": "2026-11-11T09:59:48Z", "IsDir": true},
  {"Path": "a/b/deep report.md", "Name": "deep report.md", "Size": 3, "MimeType": "text/markdown", "ModTime": "2026-11-11T09:59:48Z", "IsDir": false}
]}}
"""#

@Suite(.serialized)
struct RemoteSearchTests {
    @Test func includeRuleEscapesRegexCharacters() {
        #expect(RemoteSearch.includeRule(for: "report") == "*{{(?i)report}}*")
        #expect(RemoteSearch.includeRule(for: "a.b(1)") == #"*{{(?i)a\.b\(1\)}}*"#)
    }

    @Test func matchIgnoresCase() {
        #expect(RemoteSearch.matches(name: "Q3 REPORT.pdf", query: "report"))
        #expect(!RemoteSearch.matches(name: "notes.txt", query: "report"))
    }

    @Test func sendsRecursiveFilteredAsyncList() async throws {
        SearchURLProtocol.reset(statusReplies: [finishedListing])
        _ = try await makeSearchClient().search(fs: "gdrive:", query: "report", maxDepth: 4, pollInterval: .milliseconds(1))

        let body = try #require(SearchURLProtocol.bodies(for: "operations/list").first)
        #expect(body["fs"] as? String == "gdrive:")
        #expect(body["_async"] as? Bool == true)
        #expect((body["opt"] as? [String: Any])?["recurse"] as? Bool == true)
        #expect((body["_filter"] as? [String: Any])?["IncludeRule"] as? [String] == ["*{{(?i)report}}*"])
        #expect((body["_config"] as? [String: Any])?["MaxDepth"] as? Int == 4)
    }

    @Test func pollsUntilFinishedAndDropsUnmatchedFolders() async throws {
        SearchURLProtocol.reset(statusReplies: [#"{"finished": false}"#, #"{"finished": false}"#, finishedListing])
        let results = try await makeSearchClient().search(fs: "gdrive:", query: "report", pollInterval: .milliseconds(1))

        #expect(results.map(\.path) == ["Report.pdf", "a/Reports", "a/b/deep report.md"])
        #expect(SearchURLProtocol.bodies(for: "job/status").count == 3)
        #expect(SearchURLProtocol.bodies(for: "job/status").first?["jobid"] as? Int == 42)
    }

    @Test func failedJobThrowsItsError() async throws {
        SearchURLProtocol.reset(statusReplies: [#"{"finished": true, "success": false, "error": "directory not found"}"#])
        await #expect(throws: RcloneError.self) {
            _ = try await makeSearchClient().search(fs: "gdrive:", query: "x", pollInterval: .milliseconds(1))
        }
    }

    @Test func cancellingStopsTheJob() async throws {
        SearchURLProtocol.reset(statusReplies: [], neverFinish: true)
        let client = makeSearchClient()
        let task = Task { try await client.search(fs: "gdrive:", query: "report", pollInterval: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(60))
        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let stop = try #require(SearchURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }
}
