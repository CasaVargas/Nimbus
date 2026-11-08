import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// End-to-end check against a real rclone: preview, approve, run, versions,
/// and the removal limit, on a scratch local-to-local tree. Opt-in, because
/// it spawns `rclone rcd`:
///
///     TEST_RUNNER_NIMBUS_LIVE_RCLONE=/opt/homebrew/bin/rclone xcodebuild test \
///       -only-testing:NimbusTests/BackupLiveTests …
enum LiveRclone {
    static var path: String? { ProcessInfo.processInfo.environment["NIMBUS_LIVE_RCLONE"] }
}

@Suite("BackupLive", .serialized, .enabled(if: LiveRclone.path != nil))
@MainActor
struct BackupLiveTests {
    static let port = 5598

    private struct Tree {
        let root: URL
        var src: URL { root.appendingPathComponent("src") }
        var dst: URL { root.appendingPathComponent("dst") }
    }

    private func makeTree() throws -> Tree {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupLive-\(UUID().uuidString)")
        let tree = Tree(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: tree.src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tree.dst.appendingPathComponent("sub"), withIntermediateDirectories: true)
        func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }
        try write("new", tree.src.appendingPathComponent("new.txt"))
        try write("same", tree.src.appendingPathComponent("same.txt"))
        try write("same", tree.dst.appendingPathComponent("same.txt"))
        try write("changed-src-longer", tree.src.appendingPathComponent("sub/changed.txt"))
        try write("old", tree.dst.appendingPathComponent("sub/changed.txt"))
        try write("gone", tree.dst.appendingPathComponent("onlydst.txt"))
        try write("skip", tree.src.appendingPathComponent("skip.log"))
        // Same size and mtime would make rclone treat them as equal.
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_577_836_800)],
                             ofItemAtPath: tree.dst.appendingPathComponent("sub/changed.txt").path)
        return tree
    }

    private func startDaemon(config: URL) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: LiveRclone.path!)
        process.arguments = ["rcd", "--config", config.path, "--rc-no-auth", "--rc-addr", "127.0.0.1:\(Self.port)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let client = RcloneClient(port: Self.port)
        for _ in 0..<50 {
            if (try? await client.listJobs()) != nil { return process }
            try await Task.sleep(for: .milliseconds(100))
        }
        process.terminate()
        throw CancellationError()
    }

    @Test func previewApproveRunAndVersions() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let config = tree.root.appendingPathComponent("empty.conf")
        try Data().write(to: config)
        let daemon = try await startDaemon(config: config)
        defer { daemon.terminate() }
        let client = RcloneClient(port: Self.port)

        let store = BackupStore(file: BackupsFile(url: tree.root.appendingPathComponent("backups-v1.json")))
        await store.load()
        var job = BackupJob.new(source: .local(path: tree.src.path), destination: .local(path: tree.dst.path), now: Date())
        job.excludes = ["*.log"]
        await store.upsert(job)

        // Preview lists exactly the copy, replace and remove sets.
        let previewer = BackupPreviewer(client: client, pollInterval: .milliseconds(50))
        await previewer.run(job: job)
        guard case .finished(let preview) = previewer.state else {
            Issue.record("preview did not finish: \(previewer.state)")
            return
        }
        #expect(preview.willCopy == ["new.txt"])
        #expect(preview.willReplace == ["sub/changed.txt"])
        #expect(preview.willRemove == ["onlydst.txt"])
        #expect(preview.errors.isEmpty)
        #expect(preview.canApprove)
        #expect(FileManager.default.fileExists(atPath: tree.dst.appendingPathComponent("onlydst.txt").path),
                "a dry run must not change anything")

        // Approve and back up now.
        await store.approve(id: job.id, fingerprint: preview.fingerprint)
        let transfers = TransferStore(history: InMemoryTransferHistory())
        let runner = BackupRunner(store: store, transfers: transfers, client: client, isDaemonConnected: { true })
        transfers.startPolling(client: client)
        defer { transfers.stopPolling() }
        await runner.enqueue(job.id, trigger: .manual)
        #expect(runner.runningJobID == job.id)
        for _ in 0..<100 where store.job(id: job.id)?.lastRun == nil {
            try await Task.sleep(for: .milliseconds(100))
        }

        let lastRun = try #require(store.job(id: job.id)?.lastRun)
        #expect(lastRun.outcome == .completed)
        #expect(lastRun.copied == 2)
        #expect(lastRun.removed == 1, "onlydst.txt left the destination")
        #expect(lastRun.replaced == 1, "the old sub/changed.txt went to versions")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: tree.dst.appendingPathComponent("new.txt").path))
        #expect(!fm.fileExists(atPath: tree.dst.appendingPathComponent("onlydst.txt").path))
        #expect(!fm.fileExists(atPath: tree.dst.appendingPathComponent("skip.log").path))
        #expect(try String(contentsOf: tree.dst.appendingPathComponent("sub/changed.txt"), encoding: .utf8) == "changed-src-longer")
        let versionsRoot = tree.dst.appendingPathComponent(".nimbus-versions")
        let stamps = try fm.contentsOfDirectory(atPath: versionsRoot.path)
        #expect(stamps.count == 1)
        let stamp = versionsRoot.appendingPathComponent(try #require(stamps.first))
        #expect(fm.fileExists(atPath: stamp.appendingPathComponent("onlydst.txt").path))
        #expect(try String(contentsOf: stamp.appendingPathComponent("sub/changed.txt"), encoding: .utf8) == "old")

        // A second preview sees nothing to do, and the versions folder is left alone.
        await previewer.run(job: try #require(store.job(id: job.id)))
        guard case .finished(let second) = previewer.state else {
            Issue.record("second preview did not finish")
            return
        }
        #expect(second.isEmpty)
    }

    @Test func emptySourceHitsRemovalLimitInPreview() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let config = tree.root.appendingPathComponent("empty.conf")
        try Data().write(to: config)
        let daemon = try await startDaemon(config: config)
        defer { daemon.terminate() }

        let emptySource = tree.root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptySource, withIntermediateDirectories: true)
        var job = BackupJob.new(source: .local(path: emptySource.path), destination: .local(path: tree.dst.path), now: Date())
        job.removalLimit = 2

        let previewer = BackupPreviewer(client: RcloneClient(port: Self.port), pollInterval: .milliseconds(50))
        await previewer.run(job: job)
        guard case .finished(let preview) = previewer.state else {
            Issue.record("preview did not finish: \(previewer.state)")
            return
        }
        #expect(preview.limitHit)
        #expect(preview.canApprove == false)
        #expect(preview.willRemove.count == 3)
        #expect(FileManager.default.fileExists(atPath: tree.dst.appendingPathComponent("onlydst.txt").path))
    }
}
