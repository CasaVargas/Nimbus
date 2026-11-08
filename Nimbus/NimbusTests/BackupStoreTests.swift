import Foundation
import Testing
@testable import Nimbus

@Suite("BackupStore", .serialized)
@MainActor
struct BackupStoreTests {
    private func tempFile() -> BackupsFile {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupStoreTests-\(UUID().uuidString)", isDirectory: true)
        return BackupsFile(url: dir.appendingPathComponent("backups-v1.json"))
    }

    private func job(name: String = "Docs") -> BackupJob {
        var job = BackupJob.new(
            source: .local(path: "/Users/j/Documents"),
            destination: .cloud(remote: "b2", path: "mac"),
            now: Date(timeIntervalSince1970: 1_794_000_000)
        )
        job.name = name
        return job
    }

    @Test func missingFileLoadsEmpty() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        #expect(store.jobs.isEmpty)
        #expect(store.loadState == .loaded)
    }

    @Test func roundTripPreservesJobs() async {
        let file = tempFile()
        let store = BackupStore(file: file)
        await store.load()
        await store.upsert(job(name: "A"))
        await store.upsert(job(name: "B"))

        let reloaded = BackupStore(file: file)
        await reloaded.load()
        #expect(reloaded.jobs == store.jobs)
        #expect(reloaded.jobs.map(\.name) == ["A", "B"])
    }

    @Test func upsertReplacesById() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        var job = job(name: "A")
        await store.upsert(job)
        job.name = "A2"
        await store.upsert(job)
        #expect(store.jobs.map(\.name) == ["A2"])
    }

    @Test func deleteRemoves() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        let job = job()
        await store.upsert(job)
        await store.delete(id: job.id)
        #expect(store.jobs.isEmpty)
    }

    @Test func corruptFileIsQuarantinedAndReported() async throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.fileURL)

        let store = BackupStore(file: file)
        await store.load()
        guard case .corrupt(let quarantined) = store.loadState else {
            Issue.record("expected corrupt, got \(store.loadState)")
            return
        }
        let moved = try #require(quarantined)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
        #expect(store.jobs.isEmpty)
    }

    @Test func unknownVersionIsReadOnlyAndUntouched() async throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"version": 9, "jobs": []}"#.utf8)
        try original.write(to: file.fileURL)

        let store = BackupStore(file: file)
        await store.load()
        #expect(store.loadState == .readOnly(version: 9))
        await store.upsert(job())
        #expect(try Data(contentsOf: file.fileURL) == original)
        #expect(store.jobs.isEmpty)
    }

    @Test func approveSetsFingerprintAndDate() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        let job = job()
        await store.upsert(job)
        let now = Date(timeIntervalSince1970: 1_794_100_000)
        await store.approve(id: job.id, fingerprint: job.fingerprint, now: now)
        #expect(store.job(id: job.id)?.isApproved == true)
        #expect(store.job(id: job.id)?.approvedAt == now)
    }

    @Test func approveIgnoresStaleFingerprint() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        var job = job()
        await store.upsert(job)
        let stale = job.fingerprint
        job.excludes.append("*.tmp")
        await store.upsert(job)
        await store.approve(id: job.id, fingerprint: stale)
        #expect(store.job(id: job.id)?.isApproved == false)
        #expect(store.job(id: job.id)?.approvedAt == nil)
    }

    @Test func recordRunUpdatesLastRunOnly() async {
        let store = BackupStore(file: tempFile())
        await store.load()
        let job = job()
        await store.upsert(job)
        let summary = BackupRunSummary(
            startedAt: .init(timeIntervalSince1970: 1), finishedAt: .init(timeIntervalSince1970: 2),
            trigger: .manual, outcome: .completed, copied: 3, replaced: 0, removed: 1, errors: 0, bytes: 10
        )
        await store.recordRun(id: job.id, summary: summary)
        var expected = job
        expected.lastRun = summary
        #expect(store.job(id: job.id) == expected)
    }

    @Test func setPausedPersists() async {
        let file = tempFile()
        let store = BackupStore(file: file)
        await store.load()
        let job = job()
        await store.upsert(job)
        await store.setPaused(id: job.id, true)
        let reloaded = BackupStore(file: file)
        await reloaded.load()
        #expect(reloaded.job(id: job.id)?.isPaused == true)
    }

    @Test func fileIsPrettySortedJSON() async throws {
        let file = tempFile()
        let store = BackupStore(file: file)
        await store.load()
        await store.upsert(job())
        let text = String(decoding: try Data(contentsOf: file.fileURL), as: UTF8.self)
        #expect(text.contains(#""version" : 1"#))
        #expect(text.contains(#""kind" : "local""#))
        #expect(text.contains("\n"))
    }
}
