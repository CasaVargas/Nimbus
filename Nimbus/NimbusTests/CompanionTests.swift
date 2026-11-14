import Testing
import Foundation
import RcloneKit
@testable import Nimbus

@Suite("CloudMonitor")
@MainActor
struct CloudMonitorTests {
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    @Test func refreshLoadsListAndProbesEveryCloud() async {
        let client = MockRcloneClient()
        client.aboutResults["A:"] = .success(MockRcloneClient.emptyAbout())
        client.aboutResults["B:"] = .success(MockRcloneClient.emptyAbout())
        let status = RemoteStatusService(client: client, defaults: ScratchDefaults.make("CloudMonitor"))
        let monitor = CloudMonitor(loadRemotes: {
            [Remote(name: "A", type: "drive", config: [:]), Remote(name: "B", type: "s3", config: [:])]
        }, status: status)
        #expect(!monitor.hasLoaded)
        await monitor.refresh()
        #expect(monitor.hasLoaded)
        #expect(monitor.remotes.map(\.name) == ["A", "B"])
        #expect(Set(client.calls) == ["A:", "B:"])
    }

    @Test func failedLoadKeepsPreviousList() async {
        let status = RemoteStatusService(client: MockRcloneClient(), defaults: ScratchDefaults.make("CloudMonitor"))
        final class Flag: @unchecked Sendable { var fail = false }
        let flag = Flag()
        let monitor = CloudMonitor(loadRemotes: {
            flag.fail ? nil : [Remote(name: "A", type: "drive", config: [:])]
        }, status: status)
        await monitor.refresh()
        flag.fail = true
        await monitor.refresh()
        #expect(monitor.remotes.map(\.name) == ["A"])
    }

    @Test func refreshIfStaleSkipsFreshData() async {
        let clock = Clock()
        var loads = 0
        let status = RemoteStatusService(client: MockRcloneClient(), defaults: ScratchDefaults.make("CloudMonitor"))
        let monitor = CloudMonitor(loadRemotes: { loads += 1; return [] }, status: status, now: { clock.now })
        await monitor.refreshIfStale()
        #expect(loads == 1)
        clock.now = clock.now.addingTimeInterval(60)
        await monitor.refreshIfStale()
        #expect(loads == 1)
        clock.now = clock.now.addingTimeInterval(CloudMonitor.staleAfter)
        await monitor.refreshIfStale()
        #expect(loads == 2)
    }

    @Test func concurrentRefreshesShareOneRun() async {
        var loads = 0
        let status = RemoteStatusService(client: MockRcloneClient(), defaults: ScratchDefaults.make("CloudMonitor"))
        let monitor = CloudMonitor(loadRemotes: {
            loads += 1
            try? await Task.sleep(for: .milliseconds(50))
            return []
        }, status: status)
        async let a: Void = monitor.refresh()
        async let b: Void = monitor.refresh()
        _ = await (a, b)
        #expect(loads == 1)
    }
}

@Suite("AppRouter")
@MainActor
struct AppRouterTests {
    @Test func takeOnlyConsumesMatchingRoutes() {
        let router = AppRouter()
        router.pending = .addCloud
        #expect(router.take(where: { $0 != .addCloud }) == nil)
        #expect(router.pending == .addCloud)
        #expect(router.take(where: { $0 == .addCloud }) == .addCloud)
        #expect(router.pending == nil)
    }

    @MainActor @Test func windowRequestIsConsumedOnceAndOnlyWhenNoWindowIsOpen() {
        let router = AppRouter()
        #expect(!router.takeWindowRequest())
        router.pending = .backups(nil)  // a companion action: no request
        #expect(!router.takeWindowRequest())
        router.needsWindow = true
        #expect(router.takeWindowRequest())
        #expect(!router.takeWindowRequest())
        router.needsWindow = true
        router.isMainWindowOpen = true
        #expect(!router.takeWindowRequest())
        #expect(!router.needsWindow)
    }

    @Test func backupsRouteCarriesAnOptionalJob() {
        let router = AppRouter()
        let id = UUID()
        router.pending = .backups(id)
        #expect(router.take(where: { $0 == .addCloud }) == nil)
        #expect(router.take(where: { if case .backups = $0 { true } else { false } }) == .backups(id))
        #expect(AppRouter.Route.backups(nil) != .backups(id))
    }
}

@Suite("Companion glyph and headline")
@MainActor
struct CompanionGlyphTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func transfer(src: String, dst: String) -> Transfer {
        Transfer(jobID: 1, operation: .copy, srcFs: src, dstFs: dst, startedAt: now,
                 status: .active, origin: .manual, nimbusUUID: UUID(), progress: 0.5, eta: 90)
    }

    func busy(_ transfers: [Transfer]) -> CloudSummary.Busy? {
        let s = CloudSummaryBuilder.build(
            remotes: [Remote(name: "A", type: "drive", config: [:]), Remote(name: "B", type: "s3", config: [:])],
            statuses: ["A": .connected, "B": .connected], quotas: [:], activeTransfers: transfers,
            isInFinder: { _ in true }, providerName: { $0 }, lastConnected: [:],
            dismissedSuggestions: [], daemon: .connected, now: now)
        if case .busy(let b) = s.overall { return b }
        return nil
    }

    @Test func uploadToACloudPointsUpAndFocusesDestination() {
        let b = busy([transfer(src: "A:x", dst: "B:y")])
        #expect(b?.direction == .up)
        #expect(b?.focusCloud == "B")
        #expect(b?.eta == 90)
        #expect(CompanionGlyph.badge(for: .busy(b!)) == .uploading)
    }

    @Test func downloadToMacPointsDownAndFocusesSource() {
        let b = busy([transfer(src: "A:x", dst: "/Users/me/Downloads")])
        #expect(b?.direction == .down)
        #expect(b?.focusCloud == "A")
        #expect(b?.sentence == "Downloading 1 item to this Mac")
        #expect(CompanionGlyph.badge(for: .busy(b!)) == .downloading)
    }

    @Test func calmAndProblemStatesUseDistinctGlyphs() {
        #expect(CompanionGlyph.badge(for: .allReady) == .none)
        #expect(CompanionGlyph.badge(for: .noClouds) == .none)
        #expect(CompanionGlyph.badge(for: .engineDown("x")) == .attention)
        let row = CloudSummary.Row(id: "Work", providerType: "onedrive", providerName: "OneDrive",
                                   health: .needsSignIn, sentence: "Needs sign-in", quota: nil,
                                   isInFinder: true, tint: 0, lastConnected: nil, errorDetail: nil)
        #expect(CompanionGlyph.badge(for: .needsAttention(row)) == .attention)
        #expect(CompanionGlyph.accessibilityLabel(for: .needsAttention(row)) == "Nimbus: Work needs you to sign in")
        #expect(CompanionHeadline.title(for: .allReady) == "Everything is ready")
    }
}
