import Testing
import Foundation
@testable import Nimbus

@Suite("RemoteChangeCadence")
struct RemoteChangeCadenceTests {
    typealias Cadence = RemoteChangeCadence
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private let known: (String) -> Bool = { _ in true }

    /// State right after a full scan at t0.
    private func scanned() -> Cadence.State {
        var state = Cadence.State()
        state.recordScan(.full, foundChanges: false, at: t0)
        return state
    }

    // MARK: - Scope

    @Test func firstPassIsFull() {
        #expect(Cadence.decide(state: .init(), hotFolders: [], fullRequestedAt: nil, now: t0) == .full)
    }

    @Test func fullWhenTenMinutesOld() {
        let state = scanned()
        #expect(Cadence.decide(state: state, hotFolders: [], fullRequestedAt: nil, now: at(599)) == .none)
        #expect(Cadence.decide(state: state, hotFolders: [], fullRequestedAt: nil, now: at(600)) == .full)
    }

    @Test func fullWhenAppRequestedSinceLastFull() {
        let state = scanned()
        #expect(Cadence.decide(state: state, hotFolders: [], fullRequestedAt: at(-5), now: at(10)) == .none)
        #expect(Cadence.decide(state: state, hotFolders: [], fullRequestedAt: at(5), now: at(10)) == .full)
    }

    @Test func noHotFoldersMeansNoListing() {
        let state = scanned()
        #expect(Cadence.decide(state: state, hotFolders: [], fullRequestedAt: nil, now: at(300)) == .none)
    }

    @Test func hotScanWaitsForItsInterval() {
        let state = scanned()
        #expect(Cadence.decide(state: state, hotFolders: ["s3:a"], fullRequestedAt: nil, now: at(29)) == .none)
        #expect(Cadence.decide(state: state, hotFolders: ["s3:a"], fullRequestedAt: nil, now: at(30)) == .hot(["s3:a"]))
    }

    // MARK: - Backoff

    @Test func quietHotScansDoubleUpToCap() {
        var state = scanned()
        var now = t0
        var waits: [TimeInterval] = []
        for _ in 0..<6 {
            now = now.addingTimeInterval(state.hotInterval)
            state.recordScan(.hot(["s3:a"]), foundChanges: false, at: now)
            waits.append(state.hotInterval)
        }
        #expect(waits == [60, 120, 240, 300, 300, 300])
    }

    @Test func changeResetsTheWait() {
        var state = scanned()
        state.recordScan(.hot(["s3:a"]), foundChanges: false, at: at(30))
        state.recordScan(.hot(["s3:a"]), foundChanges: false, at: at(90))
        #expect(state.hotInterval == 120)
        state.recordScan(.hot(["s3:a"]), foundChanges: true, at: at(210))
        #expect(state.hotInterval == Cadence.baseHotInterval)
    }

    @Test func activityAfterScanResetsTheWait() {
        var state = scanned()
        state.recordScan(.hot(["s3:a"]), foundChanges: false, at: at(30))
        state.recordScan(.hot(["s3:a"]), foundChanges: false, at: at(90))
        #expect(state.hotInterval == 120)
        state.touch("s3:a", at: at(100))
        #expect(state.hotInterval == Cadence.baseHotInterval)
        #expect(Cadence.decide(state: state, hotFolders: ["s3:a"], fullRequestedAt: nil, now: at(120)) == .hot(["s3:a"]))
    }

    @Test func quietFullScanKeepsTheWait() {
        var state = scanned()
        state.recordScan(.hot(["s3:a"]), foundChanges: false, at: at(30))
        state.recordScan(.full, foundChanges: false, at: at(600))
        #expect(state.hotInterval == 60)
        #expect(state.lastFullScan == at(600).timeIntervalSince1970)
        #expect(state.lastScan == at(600).timeIntervalSince1970)
    }

    @Test func noneScopeRecordsNothing() {
        let before = scanned()
        var state = before
        state.recordScan(.none, foundChanges: false, at: at(50))
        #expect(state == before)
    }

    // MARK: - Hot folders

    @Test func activityExpiresAfterThirtyMinutes() {
        var state = Cadence.State()
        state.touch("s3:a", at: t0)
        state.touch("s3:b", at: at(600))
        let later = at(Cadence.hotLifetime + 1)
        #expect(state.hotFolders(at: later, pinned: [], isKnown: known) == ["s3:b"])
        state.expire(at: later)
        #expect(Array(state.activity.keys) == ["s3:b"])
    }

    @Test func pinnedFoldersNeverExpireAndComeFirst() {
        var state = Cadence.State()
        state.touch("s3:recent", at: t0)
        let folders = state.hotFolders(at: at(10 * Cadence.hotLifetime), pinned: ["s3:pinned"], isKnown: known)
        #expect(folders == ["s3:pinned"])
        let fresh = state.hotFolders(at: t0, pinned: ["s3:pinned", "s3:recent"], isKnown: known)
        #expect(fresh == ["s3:pinned", "s3:recent"])
    }

    @Test func onlyKnownFoldersAreHot() {
        var state = Cadence.State()
        state.touch("s3:known", at: t0)
        state.touch("s3:never-listed", at: t0)
        #expect(state.hotFolders(at: t0, pinned: ["s3:pinned-file"], isKnown: { $0 == "s3:known" }) == ["s3:known"])
    }

    @Test func capKeepsMostRecent() {
        var state = Cadence.State()
        for i in 0..<(Cadence.maxHotFolders + 10) {
            state.touch("s3:f\(i)", at: at(TimeInterval(i)))
        }
        let folders = state.hotFolders(at: at(100), pinned: [], isKnown: known)
        #expect(folders.count == Cadence.maxHotFolders)
        #expect(folders.first == "s3:f\(Cadence.maxHotFolders + 9)")
        #expect(!folders.contains("s3:f0"))
    }

    @Test func pinnedContainersIncludeParents() {
        let root = PinPolicy.rootKey
        let containers = Cadence.pinnedContainers(["s3:docs/report.pdf", "s3:top.txt"], rootKey: root)
        #expect(containers == ["s3:docs/report.pdf", "s3:docs", "s3:top.txt", root])
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var state = scanned()
        state.touch("s3:a", at: at(5))
        let decoded = try JSONDecoder().decode(Cadence.State.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    // MARK: - Full-scan request

    @Test func fullScanRequestRoundTrips() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(FullScanRequest.requestedAt(remote: "s3", base: base) == nil)
        FullScanRequest.request(remote: "s3", at: t0, base: base)
        #expect(FullScanRequest.requestedAt(remote: "s3", base: base) == t0)
    }

    // MARK: - Width-limited visits

    @Test func visitAllNeverExceedsWidth() async {
        let counter = InFlight()
        let containers = (0..<13).map { "s3:f\($0)" }
        let visits: [RemoteChangeVisit<Int>] = await RemoteChangeWalk.visitAll(containers, width: 4) { raw in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await counter.leave()
            return RemoteChangeVisit(container: raw, listing: [],
                                     diff: RemoteChangeDiff.Result(changed: [], deleted: [], deletedFolders: []),
                                     payload: 0)
        }
        #expect(visits.map(\.container) == containers)
        #expect(await counter.peak <= 4)
        #expect(await counter.peak >= 2)
    }

    @Test func visitAllWithNothingVisitsNothing() async {
        let counter = InFlight()
        let visits: [RemoteChangeVisit<Int>] = await RemoteChangeWalk.visitAll([]) { _ in
            await counter.enter()
            return nil
        }
        #expect(visits.isEmpty)
        #expect(await counter.total == 0)
    }

    // MARK: - Ticker

    @MainActor
    @Test func tickerSleepsTheIntervalBetweenSignals() async throws {
        let counter = InFlight()
        let sleeps = Recorder()
        let ticker = RemoteChangeTicker(interval: .seconds(30), sleep: { await sleeps.add($0); await Task.yield() }) {
            await counter.enter()
            await counter.leave()
        }
        ticker.start()
        ticker.start() // second start is a no-op
        for _ in 0..<1_000 where await counter.total < 3 { await Task.yield() }
        ticker.stop()
        #expect(!ticker.isRunning)
        #expect(await counter.total >= 3)
        #expect(await counter.peak == 1) // one loop, never overlapping
        #expect(await sleeps.durations.allSatisfy { $0 == .seconds(30) })
    }
}

private actor Recorder {
    private(set) var durations: [Duration] = []
    func add(_ duration: Duration) { durations.append(duration) }
}

private actor InFlight {
    private(set) var current = 0
    private(set) var peak = 0
    private(set) var total = 0
    func enter() { current += 1; total += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}
