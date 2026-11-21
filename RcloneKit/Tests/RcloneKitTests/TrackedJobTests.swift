import Foundation
import Testing
@testable import RcloneKit

/// Scripted daemon for the tracked-job tests only. Kept apart from
/// `MockURLProtocol` so concurrently running suites can't pop each other's
/// `job/status` replies.
private final class JobURLProtocol: URLProtocol, @unchecked Sendable {
    enum StatusAction: Sendable {
        case reply(String, status: Int = 200)
        case fail(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var statusActions: [StatusAction] = []
    nonisolated(unsafe) private static var bodies: [String: [Data]] = [:]
    /// When set, `job/status` keeps answering "not finished".
    nonisolated(unsafe) private static var neverFinish = false

    static func reset(
        statusReplies: [String] = [],
        statusActions actions: [StatusAction]? = nil,
        neverFinish: Bool = false
    ) {
        lock.withLock {
            self.statusActions = actions ?? statusReplies.map { .reply($0) }
            self.bodies = [:]
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
        let action: StatusAction = Self.lock.withLock {
            Self.bodies[endpoint, default: []].append(body)
            switch endpoint {
            case "operations/copyfile", "operations/movefile", "sync/move", "operations/purge":
                return .reply(#"{"jobid": 42}"#)
            case "job/status":
                if Self.neverFinish || Self.statusActions.isEmpty {
                    return .reply(#"{"finished": false}"#)
                }
                return Self.statusActions.removeFirst()
            case "core/stats":
                return .reply(#"""
                {"speed": 0, "bytes": 1234, "errors": 0, "checks": 1, "transfers": 3, "deletes": 4,
                 "renames": 2, "elapsedTime": 0.5, "totalBytes": 5000, "totalTransfers": 3, "totalChecks": 1}
                """#)
            default:
                return .reply("{}")
            }
        }
        switch action {
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .reply(let reply, let code):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private func makeJobClient() -> RcloneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [JobURLProtocol.self]
    return RcloneClient(port: 5572, session: URLSession(configuration: config))
}

/// What `onProgress` was called with, from whichever task called it.
private final class ProgressLog<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    var values: [Value] { lock.withLock { stored } }
    func record(_ value: Value) { lock.withLock { stored.append(value) } }
}

private let running = #"{"finished": false}"#
private let succeeded = #"{"finished": true, "success": true, "error": ""}"#
private let jobNotFound = #"{"error": "job not found", "path": "job/status", "status": 500}"#

private func failedJob(_ error: String) -> String {
    #"{"finished": true, "success": false, "error": "\#(error)"}"#
}

@Suite(.serialized)
struct TrackedJobTests {
    private func copy(
        _ client: RcloneClient = makeJobClient(),
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        try await client.copyFileAndWait(
            srcFs: "/staging/abc", srcRemote: "content.pdf",
            dstFs: "onedrive:", dstRemote: "Docs/Report.pdf",
            pollInterval: .milliseconds(1), onProgress: onProgress
        )
    }

    /// The status and message `run` fails with; nil if it doesn't fail
    /// that way.
    private func requestFailure(_ run: () async throws -> Void) async -> (status: Int, message: String)? {
        do {
            try await run()
        } catch RcloneError.requestFailed(let status, let message) {
            return (status, message)
        } catch {}
        return nil
    }

    // MARK: - Starting each kind of job

    @Test func copyStartsAnAsyncCopyOfTheNamedFile() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await copy()

        let body = try #require(JobURLProtocol.bodies(for: "operations/copyfile").first)
        #expect(body["srcFs"] as? String == "/staging/abc")
        #expect(body["srcRemote"] as? String == "content.pdf")
        #expect(body["dstFs"] as? String == "onedrive:")
        #expect(body["dstRemote"] as? String == "Docs/Report.pdf")
        #expect(body["_async"] as? Bool == true)
        #expect(body["_config"] == nil)
    }

    @Test func copyWithImmutableSendsImmutableConfig() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().copyFileAndWait(
            srcFs: "/staging/abc", srcRemote: "content.pdf",
            dstFs: "onedrive:", dstRemote: "Docs/Report.pdf",
            immutable: true, pollInterval: .milliseconds(1)
        )

        let body = try #require(JobURLProtocol.bodies(for: "operations/copyfile").first)
        let config = try #require(body["_config"] as? [String: Any])
        #expect(config["Immutable"] as? Bool == true)
    }

    @Test func moveFileStartsAnAsyncMovefile() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().moveFileAndWait(
            srcFs: "s3:", srcRemote: "a/old.txt",
            dstFs: "s3:", dstRemote: "b/new.txt",
            pollInterval: .milliseconds(1)
        )

        let body = try #require(JobURLProtocol.bodies(for: "operations/movefile").first)
        #expect(body["srcFs"] as? String == "s3:")
        #expect(body["srcRemote"] as? String == "a/old.txt")
        #expect(body["dstFs"] as? String == "s3:")
        #expect(body["dstRemote"] as? String == "b/new.txt")
        #expect(body["_async"] as? Bool == true)
        #expect(body["_config"] == nil)
    }

    @Test func moveFileWithImmutableSendsImmutableConfig() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().moveFileAndWait(
            srcFs: "s3:", srcRemote: "a/old.txt",
            dstFs: "s3:", dstRemote: "b/new.txt",
            immutable: true, pollInterval: .milliseconds(1)
        )

        let body = try #require(JobURLProtocol.bodies(for: "operations/movefile").first)
        let config = try #require(body["_config"] as? [String: Any])
        #expect(config["Immutable"] as? Bool == true)
    }

    @Test func moveDirectoryStartsAnAsyncSyncMoveThatRemovesEmptySourceFolders() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().moveDirectoryAndWait(
            srcFs: "s3:bucket/old", dstFs: "s3:bucket/new",
            pollInterval: .milliseconds(1)
        )

        let body = try #require(JobURLProtocol.bodies(for: "sync/move").first)
        #expect(body["srcFs"] as? String == "s3:bucket/old")
        #expect(body["dstFs"] as? String == "s3:bucket/new")
        #expect(body["deleteEmptySrcDirs"] as? Bool == true)
        #expect(body["_async"] as? Bool == true)
        #expect(body["_config"] == nil)
    }

    @Test func moveDirectoryWithImmutableSendsImmutableConfig() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().moveDirectoryAndWait(
            srcFs: "s3:bucket/old", dstFs: "s3:bucket/new",
            immutable: true, pollInterval: .milliseconds(1)
        )

        let body = try #require(JobURLProtocol.bodies(for: "sync/move").first)
        let config = try #require(body["_config"] as? [String: Any])
        #expect(config["Immutable"] as? Bool == true)
    }

    @Test func purgeStartsAnAsyncPurge() async throws {
        JobURLProtocol.reset(statusReplies: [succeeded])
        try await makeJobClient().purgeAndWait(fs: "s3:", remote: "bucket/old", pollInterval: .milliseconds(1))

        let body = try #require(JobURLProtocol.bodies(for: "operations/purge").first)
        #expect(body["fs"] as? String == "s3:")
        #expect(body["remote"] as? String == "bucket/old")
        #expect(body["_async"] as? Bool == true)
    }

    // MARK: - Waiting and progress

    @Test func copyWaitsForTheJobAndReportsBytes() async throws {
        JobURLProtocol.reset(statusReplies: [running, running, succeeded])
        let log = ProgressLog<Int64>()
        try await copy { log.record($0) }

        let statuses = JobURLProtocol.bodies(for: "job/status")
        #expect(statuses.count == 3)
        #expect(statuses.first?["jobid"] as? Int == 42)
        // One look at the job's own stats group per unfinished status.
        #expect(JobURLProtocol.bodies(for: "core/stats").map { $0["group"] as? String } == ["job/42", "job/42"])
        #expect(log.values == [1234, 1234])
        #expect(JobURLProtocol.bodies(for: "job/stop").isEmpty)
    }

    @Test func otherJobsReportTheirStats() async throws {
        JobURLProtocol.reset(statusReplies: [running, running, succeeded])
        let log = ProgressLog<StatsResponse>()
        try await makeJobClient().moveDirectoryAndWait(
            srcFs: "s3:a", dstFs: "s3:b", pollInterval: .milliseconds(1)
        ) { log.record($0) }

        #expect(log.values.map(\.transfers) == [3, 3])
        #expect(log.values.map(\.renames) == [2, 2])
        #expect(log.values.map(\.deletes) == [4, 4])
        #expect(JobURLProtocol.bodies(for: "job/stop").isEmpty)
    }

    // MARK: - Failures

    @Test func aFailedJobThrowsItsError() async throws {
        JobURLProtocol.reset(statusReplies: [failedJob("quota exceeded")])
        do {
            try await copy()
            Issue.record("expected failure")
        } catch let error as RcloneError {
            guard case .requestFailed(let status, let message) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(status == 500)
            #expect(message == "quota exceeded")
            #expect(!error.isDestinationConflict)
        }
    }

    @Test func anImmutableConflictIsA409DestinationConflict() async throws {
        JobURLProtocol.reset(statusReplies: [failedJob("not overwriting: immutable file modified")])
        do {
            try await copy()
            Issue.record("expected destination conflict")
        } catch let error as RcloneError {
            guard case .requestFailed(let status, let message) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(status == 409)
            #expect(message.contains("immutable file modified"))
            #expect(error.isDestinationConflict)
        }
        #expect(TrackedJob.status(forJobError: "immutable file modified") == 409)
        #expect(!RcloneError.requestFailed(status: 500, message: "boom").isDestinationConflict)
    }

    @Test func aMissingSourceIsANotFound() async throws {
        JobURLProtocol.reset(statusReplies: [failedJob("object not found")])
        #expect(await requestFailure { try await copy() }?.status == 404)

        JobURLProtocol.reset(statusReplies: [failedJob("directory not found")])
        let purge = await requestFailure {
            try await makeJobClient().purgeAndWait(fs: "s3:", remote: "gone", pollInterval: .milliseconds(1))
        }
        #expect(purge?.status == 404)
        #expect(purge?.message == "directory not found")

        #expect(TrackedJob.status(forJobError: "couldn't connect") == 500)
    }

    @Test func oneOrTwoFailedStatusChecksInARowAreRiddenOut() async throws {
        JobURLProtocol.reset(statusActions: [
            .fail(URLError(.timedOut)),
            .reply(running),
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
            .reply(succeeded),
        ])
        try await makeJobClient().moveFileAndWait(
            srcFs: "s3:", srcRemote: "a.txt", dstFs: "s3:", dstRemote: "b.txt",
            pollInterval: .milliseconds(1)
        )

        #expect(JobURLProtocol.bodies(for: "job/status").count == 5)
        #expect(JobURLProtocol.bodies(for: "job/stop").isEmpty)
    }

    @Test func threeFailedStatusChecksInARowStopTheJob() async throws {
        JobURLProtocol.reset(statusActions: [
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
            .reply(succeeded),
        ])

        await #expect(throws: URLError.self) {
            try await makeJobClient().purgeAndWait(fs: "s3:", remote: "dir", pollInterval: .milliseconds(1))
        }
        #expect(JobURLProtocol.bodies(for: "job/status").count == 3)
        let stop = try #require(JobURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }

    @Test func aJobTheDaemonNoLongerKnowsIsLost() async throws {
        JobURLProtocol.reset(statusActions: [.reply(jobNotFound, status: 500)])

        await #expect(throws: RcloneJobLostError(jobID: 42)) { try await copy() }
        let stop = try #require(JobURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }

    @Test func cancellingStopsTheJob() async throws {
        JobURLProtocol.reset(neverFinish: true)
        let client = makeJobClient()
        let task = Task { try await copy(client) }
        // Cancel only once the job is being watched: before the start
        // request has answered there is no job to stop yet.
        for _ in 0..<500 where JobURLProtocol.bodies(for: "job/status").isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        let stop = try #require(JobURLProtocol.bodies(for: "job/stop").first)
        #expect(stop["jobid"] as? Int == 42)
    }
}
