import Foundation
import Testing
@testable import RcloneKit

/// Captures the last request body; answers `operations/check` with a job id
/// and `job/status` with `statusBody`.
private final class CheckCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedURL: URL?
    nonisolated(unsafe) static var capturedBody: [String: Any]?
    nonisolated(unsafe) static var statusBody = "{}"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedURL = request.url
        Self.capturedBody = Self.bodyData(of: request)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let isStatus = request.url?.path.hasSuffix("job/status") == true
        let body = isStatus ? Self.statusBody : #"{"jobid": 9, "executeId": "x"}"#
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
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
struct CheckTests {
    private func capturingClient(status: String = "{}") -> RcloneClient {
        CheckCaptureURLProtocol.capturedURL = nil
        CheckCaptureURLProtocol.capturedBody = nil
        CheckCaptureURLProtocol.statusBody = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CheckCaptureURLProtocol.self]
        return RcloneClient(port: 5572, session: URLSession(configuration: config))
    }

    @Test func checksumRequestBody() async throws {
        let client = capturingClient()
        let jobID = try await client.startCheck(CheckRequest(srcFs: "/Users/j/Documents", dstFs: "gdrive:Docs"))

        #expect(jobID == 9)
        let url = try #require(CheckCaptureURLProtocol.capturedURL)
        #expect(url.path.hasSuffix("operations/check"))
        let body = try #require(CheckCaptureURLProtocol.capturedBody)
        #expect(body["srcFs"] as? String == "/Users/j/Documents")
        #expect(body["dstFs"] as? String == "gdrive:Docs")
        #expect(body["combined"] as? Bool == true)
        #expect(body["_async"] as? Bool == true)
        #expect(body["_config"] == nil)
    }

    @Test func sizeOnlyRequestSetsConfig() async throws {
        let client = capturingClient()
        _ = try await client.startCheck(CheckRequest(srcFs: "a:", dstFs: "b:", method: .sizeOnly))
        let body = try #require(CheckCaptureURLProtocol.capturedBody)
        let config = try #require(body["_config"] as? [String: Any])
        #expect(config["SizeOnly"] as? Bool == true)
    }

    /// Captured from rclone 1.76 comparing two folders that differ: the job
    /// succeeds, the report's own `success` is false.
    @Test func decodesStatusWithDifferences() async throws {
        let client = capturingClient(status: """
        {"duration": 0.001, "endTime": "2026-11-11T11:31:27-05:00", "error": "",
         "executeId": "x", "finished": true, "group": "job/3", "id": 3,
         "output": {"combined": ["- onlyB.txt", "* diff.txt", "+ sub/onlyA.txt", "= same.txt"],
                    "differ": ["diff.txt"], "error": [], "hashType": "md5",
                    "missingOnDst": ["sub/onlyA.txt"], "missingOnSrc": ["onlyB.txt"],
                    "status": "3 differences found", "success": false},
         "startTime": "2026-11-11T11:31:27-05:00", "success": true}
        """)
        let status = try await client.checkStatus(id: 3)
        #expect(CheckCaptureURLProtocol.capturedBody?["jobid"] as? Int == 3)
        #expect(status.finished)
        #expect(status.success)
        #expect(status.group == "job/3")
        let report = try #require(status.output)
        #expect(report.combined.count == 4)
        #expect(report.hashType == "md5")
        #expect(report.success == false)
        #expect(!report.comparedWithoutHash)
    }

    @Test func decodesRunningStatusWithoutOutput() async throws {
        let client = capturingClient(status: """
        {"duration": 0, "endTime": "", "error": "", "finished": false,
         "group": "job/4", "id": 4, "output": null, "startTime": "", "success": false}
        """)
        let status = try await client.checkStatus(id: 4)
        #expect(!status.finished)
        #expect(status.output == nil)
    }

    @Test func emptyCombinedAndNoHash() throws {
        let data = Data(#"{"combined": [], "hashType": "none", "success": true, "status": "OK"}"#.utf8)
        let report = try JSONDecoder().decode(CheckReport.self, from: data)
        #expect(report.combined.isEmpty)
        #expect(report.comparedWithoutHash)
    }

    @Test func failedJobKeepsError() throws {
        let data = Data(#"""
        {"id": 5, "group": "job/5", "finished": true, "success": false,
         "error": "directory not found", "output": {}}
        """#.utf8)
        let status = try JSONDecoder().decode(CheckJobStatus.self, from: data)
        #expect(!status.success)
        #expect(status.error == "directory not found")
        #expect(status.output == nil)
    }
}
