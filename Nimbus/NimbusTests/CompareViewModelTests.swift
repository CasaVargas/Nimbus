import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// Scriptable compare client. `startCheck` returns job 200; `checkStatus`
/// returns the scripted statuses in order, repeating the last.
private final class MockCompareClient: CompareRcloneClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [CheckRequest] = []
    private var _stopped: [Int] = []
    private var _statuses: [CheckJobStatus] = []
    private var _startError: Error?
    private var _statusError: Error?
    var onStatus: (@Sendable () async -> Void)?

    var requests: [CheckRequest] { lock.withLock { _requests } }
    var stopped: [Int] { lock.withLock { _stopped } }

    func script(_ statuses: [CheckJobStatus]) { lock.withLock { _statuses = statuses } }
    func failStart(_ error: Error) { lock.withLock { _startError = error } }
    func failStatus(_ error: Error) { lock.withLock { _statusError = error } }

    func listRemotes() async throws -> [String] { ["gdrive", "b2"] }

    func startCheck(_ request: CheckRequest) async throws -> Int {
        try lock.withLock {
            if let _startError { throw _startError }
            _requests.append(request)
            return 200
        }
    }

    func checkStatus(id: Int) async throws -> CheckJobStatus {
        if let onStatus { await onStatus() }
        return try lock.withLock {
            if let _statusError { throw _statusError }
            let next = _statuses.count > 1 ? _statuses.removeFirst() : _statuses.first
            return next ?? CheckJobStatus(id: id, group: "job/\(id)", finished: false, success: false)
        }
    }

    func getStats(group: String?) async throws -> StatsResponse {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(StatsResponse.self, from: Data("""
        {"speed": 0, "bytes": 0, "errors": 0, "checks": 42, "transfers": 0, "deletes": 0,
         "elapsedTime": 1, "totalBytes": 0, "totalTransfers": 0, "totalChecks": 42}
        """.utf8))
    }

    func stopJob(id: Int) async throws { lock.withLock { _stopped.append(id) } }
}

private actor CompareStateLog {
    var states: [CompareViewModel.State] = []
    func append(_ state: CompareViewModel.State) { states.append(state) }
}

@Suite("CompareResult")
struct CompareResultTests {
    @Test func parsesEverySign() {
        let result = CompareResult(combined: [
            "= same.txt", "* diff.txt", "+ sub/onlyA.txt", "- onlyB.txt", "! broken.txt",
        ])
        #expect(result.same == ["same.txt"])
        #expect(result.differ == ["diff.txt"])
        #expect(result.onlyInA == ["sub/onlyA.txt"])
        #expect(result.onlyInB == ["onlyB.txt"])
        #expect(result.errors == ["broken.txt"])
        #expect(result.total == 5)
        #expect(!result.matches)
    }

    @Test func keepsSpacesAndSorts() {
        let result = CompareResult(combined: ["= file 10.txt", "= My Folder/file 2.txt", "= file 2.txt"])
        #expect(result.same == ["file 2.txt", "file 10.txt", "My Folder/file 2.txt"])
    }

    @Test func skipsUnknownAndMalformedLines() {
        let result = CompareResult(combined: ["", "=", "=x", "? odd.txt", "= ok.txt"])
        #expect(result.same == ["ok.txt"])
        #expect(result.total == 1)
    }

    @Test func allSameMatches() {
        #expect(CompareResult(combined: ["= a", "= b"]).matches)
        #expect(CompareResult(combined: []).matches)
    }
}

@Suite("CompareViewModel", .serialized)
@MainActor
struct CompareViewModelTests {
    private let a = TransferEndpoint.local(path: "/Users/j/Documents")
    private let b = TransferEndpoint.cloud(remote: "gdrive", path: "Backup/Documents")

    private func report(_ combined: [String], hash: String = "md5") -> CheckReport {
        CheckReport(combined: combined, hashType: hash, status: "", success: false)
    }

    @Test func startsIdle() {
        #expect(CompareViewModel(client: MockCompareClient()).state == .idle)
    }

    @Test func idleRunningFinished() async throws {
        let client = MockCompareClient()
        client.script([
            CheckJobStatus(id: 200, group: "job/200", finished: false, success: false),
            CheckJobStatus(id: 200, group: "job/200", finished: true, success: true,
                           output: report(["= same.txt", "* diff.txt", "+ a.txt", "- b.txt"])),
        ])
        let model = CompareViewModel(client: client, pollInterval: .zero)
        let log = CompareStateLog()
        client.onStatus = { await log.append(await model.state) }

        await model.compare(a, b, method: .checksum)

        let request = try #require(client.requests.first)
        #expect(request.srcFs == "/Users/j/Documents")
        #expect(request.dstFs == "gdrive:Backup/Documents")
        #expect(request.method == .checksum)
        #expect(await log.states.contains(.running(checked: 42)))
        guard case .finished(let result) = model.state else {
            Issue.record("expected finished, got \(model.state)")
            return
        }
        #expect(result.same == ["same.txt"])
        #expect(result.differ == ["diff.txt"])
        #expect(result.onlyInA == ["a.txt"])
        #expect(result.onlyInB == ["b.txt"])
        #expect(!result.comparedWithoutHash)
    }

    @Test func sizeOnlyIsPassedThrough() async throws {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: true, success: true,
                                      output: report([], hash: "none"))])
        let model = CompareViewModel(client: client, pollInterval: .zero)
        await model.compare(a, b, method: .sizeOnly)
        #expect(client.requests.first?.method == .sizeOnly)
        // Size only never warns about missing hashes: it didn't ask for them.
        #expect(model.state == .finished(CompareResult(combined: [])))
    }

    @Test func noCommonHashIsFlagged() async {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: true, success: true,
                                      output: report(["= a"], hash: "none"))])
        let model = CompareViewModel(client: client, pollInterval: .zero)
        await model.compare(a, b, method: .checksum)
        #expect(model.state == .finished(CompareResult(combined: ["= a"], comparedWithoutHash: true)))
    }

    @Test func failedStart() async {
        let client = MockCompareClient()
        client.failStart(RcloneError.requestFailed(status: 500, message: "didn't find section in config file"))
        let model = CompareViewModel(client: client, pollInterval: .zero)
        await model.compare(a, b, method: .checksum)
        guard case .failed(let message) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(!message.isEmpty)
        model.reset()
        #expect(model.state == .idle)
    }

    @Test func failedJob() async {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: true, success: false,
                                      error: "network unreachable")])
        let model = CompareViewModel(client: client, pollInterval: .zero)
        await model.compare(a, b, method: .checksum)
        #expect(model.state == .failed("network unreachable"))
    }

    @Test func finishedWithoutReportFails() async {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: true, success: true)])
        let model = CompareViewModel(client: client, pollInterval: .zero)
        await model.compare(a, b, method: .checksum)
        guard case .failed = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
    }

    @Test func stopStopsJobAndReturnsToIdle() async {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: false, success: false)])
        let model = CompareViewModel(client: client, pollInterval: .milliseconds(5))
        let task = Task { await model.compare(a, b, method: .checksum) }
        while !model.isRunning || client.requests.isEmpty { await Task.yield() }
        await model.stop()
        await task.value
        #expect(model.state == .idle)
        #expect(client.stopped == [200])
    }

    @Test func cancelledTaskStopsJob() async {
        let client = MockCompareClient()
        client.script([CheckJobStatus(id: 200, group: "job/200", finished: false, success: false)])
        let model = CompareViewModel(client: client, pollInterval: .milliseconds(5))
        let task = Task { await model.compare(a, b, method: .checksum) }
        while client.requests.isEmpty { await Task.yield() }
        task.cancel()
        await task.value
        #expect(model.state == .idle)
        #expect(client.stopped == [200])
    }

    @Test func loadsRemotes() async {
        let model = CompareViewModel(client: MockCompareClient())
        await model.loadRemotes()
        #expect(model.remoteNames == ["gdrive", "b2"])
    }
}
