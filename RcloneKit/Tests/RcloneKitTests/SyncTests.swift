import Foundation
import Testing
@testable import RcloneKit

/// Captures the last request and its JSON body, answering `{"jobid": 7}`.
/// rclone's sync calls read `_config`, `_filter` and the report flags from
/// the JSON body, so tests pin the body itself, not just the endpoint.
private final class SyncCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedURL: URL?
    nonisolated(unsafe) static var capturedBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedURL = request.url
        Self.capturedBody = Self.bodyData(of: request)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"jobid": 7}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite(.serialized)
struct SyncTests {
    private func capturingClient() -> RcloneClient {
        SyncCaptureURLProtocol.capturedURL = nil
        SyncCaptureURLProtocol.capturedBody = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncCaptureURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    @Test func dryRunPreviewBody() async throws {
        let client = capturingClient()
        let request = SyncRequest(
            operation: .sync,
            srcFs: "/Users/j/Documents",
            dstFs: "b2:x",
            dryRun: true,
            backupDir: "b2:x/.nimbus-versions/2026-11-08 160000",
            maxDelete: 100,
            excludeRules: ["*.tmp", "/.nimbus-versions/**"],
            reports: [.missingOnDst, .missingOnSrc, .differ, .error]
        )
        let jobID = try await client.startSync(request)

        #expect(jobID == 7)
        let url = try #require(SyncCaptureURLProtocol.capturedURL)
        #expect(url.path.hasSuffix("sync/sync"))
        let body = try #require(SyncCaptureURLProtocol.capturedBody)
        #expect(body["srcFs"] as? String == "/Users/j/Documents")
        #expect(body["dstFs"] as? String == "b2:x")
        #expect(body["_async"] as? Bool == true)
        let config = try #require(body["_config"] as? [String: Any])
        #expect(config["DryRun"] as? Bool == true)
        #expect(config["BackupDir"] as? String == "b2:x/.nimbus-versions/2026-11-08 160000")
        #expect(config["MaxDelete"] as? Int == 100)
        #expect(config.count == 3)
        let filter = try #require(body["_filter"] as? [String: Any])
        #expect(filter["ExcludeRule"] as? [String] == ["*.tmp", "/.nimbus-versions/**"])
        for key in ["missingOnDst", "missingOnSrc", "differ", "error"] {
            #expect(body[key] as? Bool == true, "report \(key)")
        }
        #expect(body["match"] == nil)
        #expect(body["combined"] == nil)
    }

    @Test func plainCopyBodyHasNoConfigOrFilter() async throws {
        let client = capturingClient()
        _ = try await client.startSync(SyncRequest(operation: .copy, srcFs: "a:", dstFs: "b:"))

        let url = try #require(SyncCaptureURLProtocol.capturedURL)
        #expect(url.path.hasSuffix("sync/copy"))
        let body = try #require(SyncCaptureURLProtocol.capturedBody)
        #expect(body["_config"] == nil)
        #expect(body["_filter"] == nil)
        for key in ["missingOnDst", "missingOnSrc", "differ", "error"] {
            #expect(body[key] == nil, "report \(key)")
        }
        #expect(Set(body.keys) == ["srcFs", "dstFs", "_async"])
    }

    @Test func legacySyncStillPostsToSyncSync() async throws {
        let client = capturingClient()
        _ = try await client.sync(srcFs: "a:", dstFs: "b:")
        #expect(SyncCaptureURLProtocol.capturedURL?.path.hasSuffix("sync/sync") == true)
        #expect(SyncCaptureURLProtocol.capturedBody?["_config"] == nil)
    }
}

struct SyncDecodingTests {
    @Test func jobStatusDecodesSyncReport() throws {
        let json = #"""
        {"duration": 0.009, "endTime": "2026-11-08T16:06:32.962317-05:00", "error": "",
         "executeId": "4b48", "finished": true, "group": "job/1", "id": 1,
         "output": {"missingOnDst": ["new.txt"], "differ": ["sub/changed.txt"],
                    "missingOnSrc": ["onlydst.txt"], "error": []},
         "startTime": "2026-11-08T16:06:32.953089-05:00", "success": true}
        """#
        let job = try JSONDecoder().decode(Job.self, from: Data(json.utf8))
        #expect(job.output?.differ == ["sub/changed.txt"])
        #expect(job.output?.missingOnDst == ["new.txt"])
        #expect(job.output?.missingOnSrc == ["onlydst.txt"])
        #expect(job.output?.error == [])
    }

    @Test(arguments: [#""output": {"url": "https://x"},"#, #""output": 5,"#])
    func jobStatusWithForeignOutputDecodes(outputField: String) throws {
        let json = """
        {"duration": 1, "endTime": "", "error": "", "finished": true, "group": "job/2", "id": 2,
         \(outputField) "startTime": "", "success": true}
        """
        let job = try JSONDecoder().decode(Job.self, from: Data(json.utf8))
        #expect(job.id == 2)
        #expect(job.output == nil)
    }

    @Test func jobStatusWithoutOutputDecodes() throws {
        let json = #"""
        {"duration": 1, "endTime": "", "error": "", "finished": false, "group": "job/3", "id": 3,
         "startTime": "", "success": false}
        """#
        let job = try JSONDecoder().decode(Job.self, from: Data(json.utf8))
        #expect(job.output == nil)
        #expect(job.finished == false)
    }

    @Test func statsDecodesRenamesAndListed() throws {
        let json = #"""
        {"bytes": 27, "checks": 5, "deletedDirs": 0, "deletes": 1, "elapsedTime": 1.55,
         "errors": 0, "eta": null, "fatalError": false, "listed": 8, "renames": 1,
         "retryError": false, "speed": 0, "totalBytes": 27, "totalChecks": 5,
         "totalTransfers": 2, "transferTime": 0.0013, "transfers": 2}
        """#
        let stats = try JSONDecoder().decode(StatsResponse.self, from: Data(json.utf8))
        #expect(stats.renames == 1)
        #expect(stats.listed == 8)
        #expect(stats.lastError == nil)
    }

    @Test func statsDecodesLastError() throws {
        let json = #"""
        {"bytes": 0, "checks": 0, "deletes": 1, "elapsedTime": 1, "errors": 2, "lastError": "--max-delete threshold reached",
         "speed": 0, "totalBytes": 0, "totalChecks": 0, "totalTransfers": 0, "transfers": 0}
        """#
        let stats = try JSONDecoder().decode(StatsResponse.self, from: Data(json.utf8))
        #expect(stats.lastError == "--max-delete threshold reached")
        #expect(stats.deletes == 1)
    }
}
