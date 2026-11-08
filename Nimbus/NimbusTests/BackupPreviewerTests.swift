import Foundation
import Testing
import RcloneKit
@testable import Nimbus

@Suite("BackupPreviewer", .serialized)
@MainActor
struct BackupPreviewerTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000)

    private func job(_ mutate: (inout BackupJob) -> Void = { _ in }) -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/Documents"),
                                destination: .cloud(remote: "b2", path: "mac"), now: now)
        mutate(&job)
        return job
    }

    private func previewer(_ client: MockBackupClient) -> BackupPreviewer {
        BackupPreviewer(client: client, pollInterval: .zero, now: { self.now })
    }

    private static let report = #"{"missingOnDst": ["new.txt"], "differ": ["sub/changed.txt"], "missingOnSrc": ["onlydst.txt"], "error": []}"#

    @Test func previewSendsDryRunRequest() async throws {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(id: 100, finished: true, success: true, output: Self.report)])
        await previewer(client).run(job: job())
        let request = try #require(client.requests.first)
        #expect(request.dryRun)
        #expect(request.reports.contains(.missingOnSrc))
        #expect(request.operation == .sync)
    }

    @Test func previewMapsReportLists() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(id: 100, finished: true, success: true, output: Self.report)])
        client.setStats(group: "job/100", BackupFixtures.stats(transfers: 2, deletes: 1, renames: 0, bytes: 27))
        let job = job()
        let previewer = previewer(client)
        await previewer.run(job: job)
        guard case .finished(let preview) = previewer.state else {
            Issue.record("expected finished, got \(previewer.state)")
            return
        }
        #expect(preview.willCopy == ["new.txt"])
        #expect(preview.willReplace == ["sub/changed.txt"])
        #expect(preview.willRemove == ["onlydst.txt"])
        #expect(preview.errors.isEmpty)
        #expect(preview.approxBytes == 27)
        #expect(preview.fingerprint == job.fingerprint)
        #expect(preview.finishedAt == now)
        #expect(preview.limitHit == false)
        #expect(preview.canApprove)
        #expect(preview.needsRemovalConfirmation == false)
        #expect(preview.isEmpty == false)
    }

    @Test func previewReportsListedWhileChecking() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [
            BackupFixtures.job(id: 100, finished: false),
            BackupFixtures.job(id: 100, finished: false),
            BackupFixtures.job(id: 100, finished: true, success: true, output: Self.report),
        ])
        client.setStats(group: "job/100", BackupFixtures.listedStats(400))
        let previewer = previewer(client)
        let seen = StateLog()
        client.onJobStatus = { _ in await seen.append(await previewer.state) }
        await previewer.run(job: job())
        #expect(await seen.states.contains(.checking(listed: 400)))
    }

    @Test func limitHitIsFinishedNotFailed() async {
        let client = MockBackupClient()
        client.setStats(group: "job/100", BackupFixtures.stats(transfers: 0, deletes: 2, renames: 0,
                                                               lastError: "--max-delete threshold reached"))
        client.script(jobID: 100, [BackupFixtures.job(
            id: 100, finished: true, success: false, error: "failed to delete 4 files",
            output: #"{"missingOnDst": [], "differ": [], "missingOnSrc": ["a", "b", "c", "d", "e", "f"], "error": []}"#
        )])
        let previewer = previewer(client)
        await previewer.run(job: job { $0.removalLimit = 2 })
        guard case .finished(let preview) = previewer.state else {
            Issue.record("expected finished, got \(previewer.state)")
            return
        }
        #expect(preview.limitHit)
        // The real run would stop at the same limit, so approving is pointless:
        // the sheet sends the user to Edit instead.
        #expect(preview.canApprove == false)
        #expect(preview.needsRemovalConfirmation == false)
    }

    @Test func largeRemovalNeedsConfirmation() {
        let many = (0...100).map { "f\($0)" }
        let large = BackupPreview(willCopy: [], willReplace: [], willRemove: many, errors: [],
                                  approxBytes: 0, limitHit: false, removalLimit: nil, fingerprint: "f", finishedAt: now)
        #expect(large.needsRemovalConfirmation)
        let small = BackupPreview(willCopy: [], willReplace: [], willRemove: ["a", "b", "c"], errors: [],
                                  approxBytes: 0, limitHit: false, removalLimit: nil, fingerprint: "f", finishedAt: now)
        #expect(small.needsRemovalConfirmation == false)
    }

    @Test func reportedErrorsBlockApproval() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(
            id: 100, finished: true, success: true,
            output: #"{"missingOnDst": [], "differ": [], "missingOnSrc": [], "error": ["locked.db"]}"#
        )])
        let previewer = previewer(client)
        await previewer.run(job: job())
        guard case .finished(let preview) = previewer.state else {
            Issue.record("expected finished")
            return
        }
        #expect(preview.errors == ["locked.db"])
        #expect(preview.canApprove == false)
    }

    @Test func otherErrorFails() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(id: 100, finished: true, success: false,
                                                      error: "destination and parameter to --backup-dir mustn't overlap")])
        let previewer = previewer(client)
        await previewer.run(job: job())
        guard case .failed(let message) = previewer.state else {
            Issue.record("expected failed, got \(previewer.state)")
            return
        }
        #expect(message == "The versions folder is inside the destination. Choose a folder outside it.")
    }

    @Test func missingSourceFailsWithFriendlyMessage() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(id: 100, finished: true, success: false, error: "directory not found")])
        let previewer = previewer(client)
        await previewer.run(job: job())
        #expect(previewer.state == .failed("The source folder isn't available. Is the drive connected?"))
    }

    /// rclone 1.76 returns every requested list, empty when nothing changes.
    /// No report at all means this rclone can't preview: never show "nothing
    /// will change" for it.
    @Test func missingReportFailsInsteadOfLookingEmpty() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(id: 100, finished: true, success: true)])
        let previewer = previewer(client)
        await previewer.run(job: job())
        #expect(previewer.state == .failed(BackupPreviewer.noReportMessage))
    }

    @Test func cancelStopsJob() async {
        let client = MockBackupClient()
        let previewer = previewer(client)
        client.onJobStatus = { _ in await previewer.cancel() }
        await previewer.run(job: job())
        #expect(client.stopped == [100])
        #expect(previewer.state == .idle)
    }

    @Test func emptyPreviewIsEmpty() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(
            id: 100, finished: true, success: true,
            output: #"{"missingOnDst": [], "differ": [], "missingOnSrc": [], "error": []}"#
        )])
        let previewer = previewer(client)
        await previewer.run(job: job())
        guard case .finished(let preview) = previewer.state else {
            Issue.record("expected finished")
            return
        }
        #expect(preview.isEmpty)
    }

    @Test func addOnlyPreviewNeverListsRemovals() async {
        let client = MockBackupClient()
        client.script(jobID: 100, [BackupFixtures.job(
            id: 100, finished: true, success: true,
            output: #"{"missingOnDst": ["n"], "differ": [], "error": []}"#
        )])
        let previewer = previewer(client)
        await previewer.run(job: job { $0.mode = .addOnly })
        guard case .finished(let preview) = previewer.state else {
            Issue.record("expected finished")
            return
        }
        #expect(preview.willRemove.isEmpty)
        #expect(client.requests.first?.reports.contains(.missingOnSrc) == false)
    }
}

/// Collects previewer states seen from the mock's callback.
actor StateLog {
    private(set) var states: [BackupPreviewer.State] = []
    func append(_ state: BackupPreviewer.State) { states.append(state) }
}
