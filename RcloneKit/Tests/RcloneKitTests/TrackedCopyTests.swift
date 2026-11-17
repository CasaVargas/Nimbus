import Foundation
import Testing
@testable import RcloneKit

/// Scripted daemon for the tracked-copy tests only. Kept apart from
/// `MockURLProtocol` so concurrently running suites can't pop each other's
/// `job/status` replies.
private final class CopyURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statusReplies: [String] = []
    nonisolated(unsafe) private static var bodies: [String: [Data]] = [:]
    /// When set, `job/status` keeps answering "not finished".
    nonisolated(unsafe) private static var neverFinish = false
    /// When set, `job/status` answers with this HTTP status.
    nonisolated(unsafe) private static var statusFailure: Int?

    static func reset(statusReplies replies: [String], neverFinish: Bool = false, statusFailure: Int? = nil) {
        lock.withLock {
            statusReplies = replies
            bodies = [:]
            self.neverFinish = neverFinish
            self.statusFailure = statusFailure
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
        let (reply, code): (String, Int) = Self.lock.withLock {
            Self.bodies[endpoint, default: []].append(body)
            switch endpoint {
            case "operations/copyfile":
                return (#"{"jobid": 42}"#, 200)
            case "job/status":
                if let failure = Self.statusFailure {
                    return (#"{"error": "job not found", "path": "job/status", "status": \#(failure)}"#, failure)
                }
                if Self.neverFinish || Self.statusReplies.isEmpty { return (#"{"finished": false}"#, 200) }
                return (Self.statusReplies.removeFirst(), 200)
            case "core/stats":
                return (#"""
                {"speed": 0, "bytes": 1234, "errors": 0, "checks": 0, "transfers": 0, "deletes": 0,
                 "elapsedTime": 0.5, "totalBytes": 5000, "totalTransfers": 1, "totalChecks": 0}
                """#, 200)
            default:
                return ("{}", 200)
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeCopyClient() -> RcloneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CopyURLProtocol.self]
    return RcloneClient(port: 5572, session: URLSession(configuration: config))
}

/// What `onProgress` was called with, from whichever task called it.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int64] = []

    var values: [Int64] { lock.withLock { stored } }
    func record(_ bytes: Int64) { lock.withLock { stored.append(bytes) } }
}

private let running = #"{"finished": false}"#
private let succeeded = #"{"finished": true, "success": true, "error": ""}"#

@Suite(.serialized)
struct TrackedCopyTests {
    private func copy(
        _ client: RcloneClient = makeCopyClient(),
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        try await client.copyFileAndWait(
            srcFs: "/staging/abc", srcRemote: "content.pdf",
            dstFs: "onedrive:", dstRemote: "Docs/Report.pdf",
            pollInterval: .milliseconds(1), onProgress: onProgress
        )
    }

    /// The status and message a copy fails with; nil if it doesn't fail
    /// that way.
    private func copyFailure() async -> (status: Int, message: String)? {
        do {
            try await copy()
        } catch RcloneError.requestFailed(let status, let message) {
            return (status, message)
        } catch {}
        return nil
    }

    @Test func startsAnAsyncCopyOfTheNamedFile() async throws {
        CopyURLProtocol.reset(statusReplies: [succeeded])
        try await copy()

        let body = try #require(CopyURLProtocol.bodies(for: "operations/copyfile").first)
        #expect(body["srcFs"] as? String == "/staging/abc")
        #expect(body["srcRemote"] as? String == "content.pdf")
        #expect(body["dstFs"] as? String == "onedrive:")
        #expect(body["dstRemote"] as? String == "Docs/Report.pdf")
        #expect(body["_async"] as? Bool == true)
    }

    @Test func waitsForTheJobAndReportsProgress() async throws {
        CopyURLProtocol.reset(statusReplies: [running, running, succeeded])
        let log = ProgressLog()
        try await copy { log.record($0) }

        let statuses = CopyURLProtocol.bodies(for: "job/status")
        #expect(statuses.count == 3)
        #expect(statuses.first?["jobid"] as? Int == 42)
        // One look at the job's own stats group per unfinished status.
        #expect(CopyURLProtocol.bodies(for: "core/stats").map { $0["group"] as? String } == ["job/42", "job/42"])
        #expect(log.values == [1234, 1234])
        #expect(CopyURLProtocol.bodies(for: "job/stop").isEmpty)
    }

    @Test func aFailedJobThrowsItsError() async throws {
        CopyURLProtocol.reset(statusReplies: [#"{"finished": true, "success": false, "error": "quota exceeded"}"#])
        let failure = await copyFailure()
        #expect(failure?.status == 500)
        #expect(failure?.message == "quota exceeded")
    }

    @Test func aMissingSourceIsANotFound() async throws {
        CopyURLProtocol.reset(statusReplies: [#"{"finished": true, "success": false, "error": "object not found"}"#])
        let failure = await copyFailure()
        #expect(failure?.status == 404)
        #expect(TrackedCopy.status(forJobError: "directory not found") == 404)
        #expect(TrackedCopy.status(forJobError: "couldn't connect") == 500)
    }

    @Test func aFailedWaitStopsTheJob() async throws {
        CopyURLProtocol.reset(statusReplies: [], statusFailure: 500)
        await #expect(throws: RcloneError.self) { try await copy() }

        let stop = try #require(CopyURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }

    @Test func cancellingStopsTheJob() async throws {
        CopyURLProtocol.reset(statusReplies: [], neverFinish: true)
        let client = makeCopyClient()
        let task = Task { try await copy(client) }
        try await Task.sleep(for: .milliseconds(60))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        let stop = try #require(CopyURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }
}
