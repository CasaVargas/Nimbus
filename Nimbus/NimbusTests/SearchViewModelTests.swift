import Foundation
import Testing
@testable import Nimbus
@testable import RcloneKit

/// Scripted `SearchClient`: per-fs results, optional delay, and a record of
/// which calls finished vs. were cancelled.
private final class ScriptedSearchClient: SearchClient, @unchecked Sendable {
    struct Script {
        var result: Result<[FileItem], Error> = .success([])
        var delay: Duration = .zero
    }

    private let lock = NSLock()
    private var scripts: [String: Script]
    private var _cancelled: [String] = []
    private var _queries: [String] = []

    init(_ scripts: [String: Script]) { self.scripts = scripts }

    var cancelled: [String] { lock.withLock { _cancelled } }
    var queries: [String] { lock.withLock { _queries } }

    func searchFiles(fs: String, query: String) async throws -> [FileItem] {
        let script = lock.withLock {
            _queries.append("\(fs)\(query)")
            return scripts[fs] ?? Script()
        }
        do {
            if script.delay > .zero { try await Task.sleep(for: script.delay) }
        } catch {
            lock.withLock { _cancelled.append(fs) }
            throw CancellationError()
        }
        return try script.result.get()
    }
}

private func item(_ path: String, dir: Bool = false) -> FileItem {
    FileItem(
        path: path, name: (path as NSString).lastPathComponent, size: 1, mimeType: "",
        modTime: nil, isDir: dir, fileID: nil, qualifiedRemotePath: path
    )
}

private func remote(_ name: String, type: String = "drive", config: [String: String] = [:]) -> Remote {
    Remote(name: name, type: type, config: config)
}

private struct Boom: Error {}

@MainActor
struct SearchViewModelTests {
    @Test func keepsResultsPerCloudAndTagsThem() async {
        let client = ScriptedSearchClient([
            "a:": .init(result: .success([item("x/report.pdf"), item("Report")])),
            "b:": .init(result: .success([item("b-report.txt")])),
            "c:": .init(result: .success([])),
        ])
        let model = SearchViewModel(client: client)
        await model.search("  report ", in: [remote("a"), remote("b"), remote("c")])

        #expect(model.query == "report")
        #expect(model.clouds.map(\.remote) == ["a", "b", "c"])
        #expect(model.clouds.allSatisfy { $0.phase == .done })
        #expect(model.clouds[0].items.map(\.qualifiedRemotePath) == ["a:Report", "a:x/report.pdf"])
        #expect(model.clouds[1].items.map(\.qualifiedRemotePath) == ["b:b-report.txt"])
        #expect(model.clouds[2].items.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func oneFailingCloudDoesNotStopTheOthers() async {
        let client = ScriptedSearchClient([
            "a:": .init(result: .failure(Boom())),
            "b:": .init(result: .success([item("report")])),
        ])
        let model = SearchViewModel(client: client)
        await model.search("report", in: [remote("a"), remote("b")])

        guard case .failed = model.clouds[0].phase else {
            Issue.record("expected a failure, got \(model.clouds[0].phase)")
            return
        }
        #expect(model.clouds[1].phase == .done)
        #expect(model.clouds[1].items.count == 1)
    }

    @Test func slowCloudTimesOutAndIsCancelled() async {
        let client = ScriptedSearchClient([
            "slow:": .init(result: .success([item("report")]), delay: .seconds(30)),
            "fast:": .init(result: .success([item("report")])),
        ])
        let model = SearchViewModel(client: client, timeout: .milliseconds(50))
        await model.search("report", in: [remote("slow"), remote("fast")])

        #expect(model.clouds[0].phase == .timedOut)
        #expect(model.clouds[1].phase == .done)
        #expect(client.cancelled == ["slow:"])
    }

    @Test func newSearchCancelsTheOldOne() async throws {
        let client = ScriptedSearchClient([
            // Long enough that it can only end by being cancelled.
            "a:": .init(result: .success([item("old")]), delay: .seconds(60)),
        ])
        let model = SearchViewModel(client: client)
        let old = Task { await model.search("old", in: [remote("a")]) }
        // Wait for the search to reach the client instead of a fixed sleep,
        // which raced on a loaded CI runner.
        let deadline = ContinuousClock.now + .seconds(10)
        while client.queries.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(client.queries == ["a:old"])
        old.cancel()
        await old.value

        #expect(client.cancelled == ["a:"])
        // The cancelled search never wrote results.
        #expect(model.clouds.first?.phase == .searching)
        #expect(model.clouds.first?.items.isEmpty == true)
    }

    @Test func clearedQueryDropsResults() async {
        let client = ScriptedSearchClient(["a:": .init(result: .success([item("report")]))])
        let model = SearchViewModel(client: client)
        await model.search("report", in: [remote("a")])
        await model.search("r", in: [remote("a")])

        #expect(model.clouds.isEmpty)
        #expect(model.query.isEmpty)
        #expect(client.queries == ["a:report"])
    }

    @Test func skipsAliasesOfConfiguredClouds() {
        let remotes = [
            remote("gdrive"),
            remote("Work", type: "alias", config: ["remote": "gdrive:Work"]),
            remote("Home", type: "alias", config: ["remote": "/Users/me"]),
        ]
        #expect(SearchViewModel.searchableRemotes(remotes).map(\.name) == ["gdrive", "Home"])
    }

    @Test func capsResultsAndKeepsTheTotal() async {
        let many = (0..<(SearchViewModel.resultCap + 25)).map { item("report-\($0)") }
        let client = ScriptedSearchClient(["a:": .init(result: .success(many))])
        let model = SearchViewModel(client: client)
        await model.search("report", in: [remote("a")])

        #expect(model.clouds[0].items.count == SearchViewModel.resultCap)
        #expect(model.clouds[0].total == SearchViewModel.resultCap + 25)
        #expect(model.clouds[0].isTruncated)
    }
}
