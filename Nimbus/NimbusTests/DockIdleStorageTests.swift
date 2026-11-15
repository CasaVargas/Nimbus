import Foundation
import Testing
@testable import Nimbus

@Suite("Idle disconnect")
@MainActor
struct IdleDisconnectTests {
    @Test func policySleepsOnlyPastTimeoutWhenNotBusy() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(!IdleDisconnectPolicy.shouldSleep(timeout: nil, lastActivity: start, now: start + 10_000, isBusy: false))
        #expect(!IdleDisconnectPolicy.shouldSleep(timeout: 300, lastActivity: start, now: start + 299, isBusy: false))
        #expect(IdleDisconnectPolicy.shouldSleep(timeout: 300, lastActivity: start, now: start + 300, isBusy: false))
        #expect(!IdleDisconnectPolicy.shouldSleep(timeout: 300, lastActivity: start, now: start + 900, isBusy: true))
    }

    @Test func intervals() {
        #expect(IdleDisconnect.never.interval == nil)
        #expect(IdleDisconnect.fiveMinutes.interval == 300)
        #expect(IdleDisconnect.oneHour.interval == 3_600)
    }

    private final class Clock { var now = Date(timeIntervalSince1970: 50_000) }

    private func makeController(
        status: RcloneDaemon.Status, idle: IdleDisconnect, busy: Bool = false
    ) -> (IdleDisconnectController, RcloneDaemon, Clock) {
        let daemon = RcloneDaemon(testStatus: status)
        let settings = AppSettings(defaults: ScratchDefaults.make("IdleDisconnect"))
        settings.idleDisconnect = idle
        let clock = Clock()
        let controller = IdleDisconnectController(
            daemon: daemon, settings: settings,
            activity: .init(hasVisibleWindow: { false }, hasActiveWork: { busy }),
            now: { clock.now }
        )
        return (controller, daemon, clock)
    }

    @Test func tickSleepsAnIdleEngineAfterTheTimeout() {
        let (controller, daemon, clock) = makeController(status: .connected, idle: .fiveMinutes)
        var slept = false
        controller.onSleep = { slept = true }

        clock.now += 299
        controller.tick()
        #expect(daemon.status == .connected)

        clock.now += 1
        controller.tick()
        #expect(daemon.status == .asleep)
        #expect(slept)
    }

    @Test func busyWorkKeepsTheEngineAwake() {
        let (controller, daemon, clock) = makeController(status: .connected, idle: .fiveMinutes, busy: true)
        clock.now += 3_600
        controller.tick()
        #expect(daemon.status == .connected)
    }

    @Test func neverMeansNever() {
        let (controller, daemon, clock) = makeController(status: .connected, idle: .never)
        clock.now += 86_400
        controller.tick()
        #expect(daemon.status == .connected)
    }

    @Test func sleepOnlyFromConnected() {
        let daemon = RcloneDaemon(testStatus: .error("boom"))
        daemon.sleep()
        #expect(daemon.status == .error("boom"))
    }
}

@Suite("Finder wake")
struct NimbusWakeTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NimbusWake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func prefsDefaultToOpeningTheApp() {
        #expect(NimbusWake.decodeOpensApp(nil))
        #expect(NimbusWake.decodeOpensApp(Data("garbage".utf8)))
        #expect(NimbusWake.decodeOpensApp(NimbusWake.encodePrefs(opensApp: false)) == false)
        #expect(NimbusWake.decodeOpensApp(NimbusWake.encodePrefs(opensApp: true)))
    }

    @Test func prefsRoundTripThroughTheContainer() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        NimbusWake.writePrefs(opensApp: false, in: dir)
        #expect(NimbusWake.readOpensApp(in: dir) == false)
        #expect(NimbusWake.readOpensApp(in: nil))
    }

    @Test func markerFreshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        let stamp = { (t: TimeInterval) in Data(String(t).utf8) }
        #expect(NimbusWake.isFresh(markerData: stamp(9_990), now: now))
        #expect(!NimbusWake.isFresh(markerData: stamp(9_900), now: now))
        #expect(!NimbusWake.isFresh(markerData: nil, now: now))
        #expect(!NimbusWake.isFresh(markerData: Data("x".utf8), now: now))
    }

    @Test func markerIsConsumedOnce() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        NimbusWake.writeLaunchMarker(in: dir, now: now)
        #expect(NimbusWake.consumeLaunchMarker(in: dir, now: now))
        #expect(!NimbusWake.consumeLaunchMarker(in: dir, now: now))
    }

    @Test func staleMarkerIsRemovedButIgnored() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        NimbusWake.writeLaunchMarker(in: dir, now: now - 600)
        #expect(!NimbusWake.consumeLaunchMarker(in: dir, now: now))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(NimbusWake.launchMarkerFileName).path))
    }
}

@Suite("Downloaded storage")
@MainActor
struct DownloadedStorageTests {
    private func file(_ id: String, _ size: Int64) -> MaterializedEntry {
        MaterializedEntry(identifier: id, filename: (id as NSString).lastPathComponent, size: size, isFolder: false)
    }

    private func folder(_ id: String) -> MaterializedEntry {
        MaterializedEntry(identifier: id, filename: (id as NSString).lastPathComponent, size: 4_096, isFolder: true)
    }

    @Test func totalsCountFilesOnly() {
        let entries = [file("g:a", 100), file("g:b", 50), folder("g:Photos")]
        #expect(DownloadedStorage.totalBytes(entries) == 150)
        #expect(DownloadedStorage.fileCount(entries) == 2)
    }

    @Test func planSkipsFoldersAndKeptItems() {
        let entries = [
            file("g:a.mov", 100),
            file("g:keep.pdf", 10),
            folder("g:Photos"),
            file("g:Photos/1.jpg", 5),
            file("g:Photoshop.psd", 7),
        ]
        let plan = DownloadedStorage.evictionPlan(entries, pinned: ["g:keep.pdf", "g:Photos"])
        #expect(plan == ["g:a.mov", "g:Photoshop.psd"])
    }

    @Test func modelLoadsAndRemoves() async {
        final class Fake { var entries: [String: [MaterializedEntry]] = [:]; var evicted: [String] = [] }
        let fake = Fake()
        fake.entries = [
            "Drive": [file("Drive:a", 1_000), file("Drive:b", 500)],
            "Box": [],
        ]
        let model = DownloadedStorageModel(source: .init(
            domains: { Array(fake.entries.keys) },
            entries: { fake.entries[$0] ?? [] },
            pins: { _ in ["Drive:b"] },
            evict: { remote, ids in
                fake.evicted += ids
                fake.entries[remote]?.removeAll { ids.contains($0.identifier) }
                return 0
            }
        ))

        await model.load()
        #expect(model.drives.map(\.remote) == ["Box", "Drive"])
        #expect(model.totalBytes == 1_500)

        await model.removeAllDownloads()
        #expect(fake.evicted == ["Drive:a"])
        #expect(model.totalBytes == 500)
        #expect(model.drives.first { $0.remote == "Drive" }?.keptCount == 1)
    }
}

@Suite("Storage settings", .serialized)
@MainActor
struct StorageSettingsViewTests {
    @Test func rendersDownloadedFilesPerDrive() async throws {
        let entry = { (id: String, size: Int64) in
            MaterializedEntry(identifier: id, filename: id, size: size, isFolder: false)
        }
        let model = DownloadedStorageModel(source: .init(
            domains: { ["Google Drive", "Dropbox", "Backups S3"] },
            entries: { remote in
                switch remote {
                case "Google Drive": [entry("g:a.mov", 1_400_000_000), entry("g:b.pdf", 2_300_000)]
                case "Dropbox": [entry("d:c.zip", 86_000_000)]
                default: []
                }
            },
            pins: { _ in [] },
            evict: { _, _ in 0 }
        ))
        await model.load()
        try SnapshotHelpers.assertHostedSnapshot(
            StorageSettingsView(model: model).preferredColorScheme(.dark),
            size: CGSize(width: 680, height: 520),
            named: "Settings-Storage"
        )
    }
}
