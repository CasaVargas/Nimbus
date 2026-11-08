import Foundation
import Testing
import RcloneKit
@testable import Nimbus

@Suite("BackupRunner", .serialized)
@MainActor
struct BackupRunnerTests {
    let now = Date(timeIntervalSince1970: 1_794_085_200) // 2026-11-08 16:00:00 EST

    struct Harness {
        let runner: BackupRunner
        let store: BackupStore
        let transfers: TransferStore
        let client: MockBackupClient
    }

    private func harness(connected: Bool = true) async -> Harness {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupRunnerTests-\(UUID().uuidString)", isDirectory: true)
        let store = BackupStore(file: BackupsFile(url: dir.appendingPathComponent("backups-v1.json")))
        await store.load()
        let transfers = TransferStore(history: InMemoryTransferHistory())
        let client = MockBackupClient()
        let runner = BackupRunner(store: store, transfers: transfers, client: client,
                                  isDaemonConnected: { connected }, now: { self.now })
        return Harness(runner: runner, store: store, transfers: transfers, client: client)
    }

    private func addJob(_ h: Harness, name: String = "Docs", approved: Bool = true,
                        _ mutate: (inout BackupJob) -> Void = { _ in }) async -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/\(name)"),
                                destination: .cloud(remote: "b2", path: name), now: now)
        job.name = name
        mutate(&job)
        await h.store.upsert(job)
        if approved { await h.store.approve(id: job.id, fingerprint: job.fingerprint, now: now) }
        return h.store.job(id: job.id)!
    }

    private func finish(_ h: Harness, rcloneJob: Int, success: Bool = true, error: String = "") async {
        await h.transfers.handleFinished(
            jobID: rcloneJob,
            job: BackupFixtures.job(id: rcloneJob, finished: true, success: success, error: error),
            stats: BackupFixtures.stats(transfers: 3, deletes: 1, renames: 2),
            now: now.addingTimeInterval(60)
        )
    }

    @Test func unapprovedJobIsRefused() async {
        let h = await harness()
        let job = await addJob(h, approved: false)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .notApproved)
        #expect(h.runner.queue.isEmpty)
    }

    @Test func daemonDownIsRefused() async {
        let h = await harness(connected: false)
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .daemonNotConnected)
    }

    @Test func approvedJobStartsWithRealRequest() async throws {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        let request = try #require(h.client.requests.first)
        #expect(request.dryRun == false)
        #expect(request.reports.isEmpty)
        let stamp = BackupRequest.stamp(for: now)
        #expect(request.backupDir == "b2:Docs/.nimbus-versions/\(stamp)")
        #expect(h.runner.runningJobID == job.id)
        let transfer = try #require(h.transfers.activeTransfers.first)
        #expect(transfer.origin == .backup)
        #expect(transfer.backup?.title == "Docs")
        #expect(transfer.backup?.hadRemovalLimit == true)
        #expect(transfer.backup?.isMirrorWithVersions == true)
        #expect(transfer.jobID == 100)
    }

    @Test func secondEnqueueOfSameJobIsRefused() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.lastRefusal == .alreadyQueuedOrRunning)
    }

    @Test func jobsRunOneAtATime() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .scheduled)
        #expect(h.client.requests.count == 1)
        #expect(h.runner.queue == [second.id])

        await finish(h, rcloneJob: 100)
        #expect(h.client.requests.count == 2)
        #expect(h.client.requests.last?.srcFs == "/Users/j/B")
        #expect(h.runner.runningJobID == second.id)
        #expect(h.transfers.activeTransfers.first?.backup?.trigger == .scheduled)
    }

    @Test func finishRecordsLastRun() async throws {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100)
        let lastRun = try #require(h.store.job(id: job.id)?.lastRun)
        #expect(lastRun.outcome == .completed)
        #expect(lastRun.copied == 3)
        #expect(lastRun.removed == 1)
        #expect(lastRun.replaced == 1)
        #expect(lastRun.trigger == .manual)
        #expect(h.runner.runningJobID == nil)
        #expect(h.runner.isRunningAnything == false)
    }

    @Test func missingSourceMessage() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await finish(h, rcloneJob: 100, success: false, error: "directory not found")
        #expect(h.store.job(id: job.id)?.lastRun?.outcome
            == .failed("The source folder isn't available. Is the drive connected?"))
    }

    @Test func limitHitRecorded() async {
        let h = await harness()
        let job = await addJob(h)
        await h.runner.enqueue(job.id, trigger: .manual)
        await h.transfers.handleFinished(
            jobID: 100,
            job: BackupFixtures.job(id: 100, finished: true, success: false, error: "failed to delete 4 files"),
            stats: BackupFixtures.stats(transfers: 0, deletes: 100, renames: 0, lastError: "--max-delete threshold reached"),
            now: now
        )
        #expect(h.store.job(id: job.id)?.lastRun?.outcome == .limitHit)
    }

    @Test func daemonRestartUnsticksQueue() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.transfers.abandonActiveTransfers()
        #expect(h.store.job(id: first.id)?.lastRun?.outcome == .failed(TransferStore.lostRunMessage))
        #expect(h.runner.runningJobID == second.id)
    }

    @Test func editedJobAfterApprovalIsRefused() async {
        let h = await harness()
        var job = await addJob(h)
        job.destination = .cloud(remote: "b2", path: "elsewhere")
        await h.store.upsert(job)
        await h.runner.enqueue(job.id, trigger: .manual)
        #expect(h.client.requests.isEmpty)
        #expect(h.runner.lastRefusal == .notApproved)
    }

    @Test func startFailureRecordsFailedRunAndContinues() async {
        let h = await harness()
        let job = await addJob(h)
        h.client.failStarts(with: URLError(.cannotConnectToHost))
        await h.runner.enqueue(job.id, trigger: .manual)
        guard case .failed = h.store.job(id: job.id)?.lastRun?.outcome else {
            Issue.record("expected a failed lastRun")
            return
        }
        #expect(h.runner.runningJobID == nil)
    }

    @Test func stopCancelsAndStartsNext() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.runner.stop(first.id)
        #expect(h.client.stopped == [100])
        #expect(h.store.job(id: first.id)?.lastRun?.outcome == .cancelled)
        #expect(h.runner.runningJobID == second.id)
    }

    @Test func stopQueuedJobRemovesIt() async {
        let h = await harness()
        let first = await addJob(h, name: "A")
        let second = await addJob(h, name: "B")
        await h.runner.enqueue(first.id, trigger: .manual)
        await h.runner.enqueue(second.id, trigger: .manual)
        await h.runner.stop(second.id)
        #expect(h.runner.queue.isEmpty)
        #expect(h.client.stopped.isEmpty)
    }
}
