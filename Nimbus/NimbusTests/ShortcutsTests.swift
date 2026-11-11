import FileProvider
import Foundation
import Testing
@testable import Nimbus

@Suite("Shortcuts")
struct ShortcutsTests {
    // MARK: - ShortcutTarget

    @Test func itemInsideCloud() {
        let target = ShortcutTarget.from(itemIdentifier: "b2:Docs/report.pdf", domain: "b2")
        #expect(target == ShortcutTarget(remote: "b2", path: "Docs/report.pdf"))
        #expect(target?.identifier == "b2:Docs/report.pdf")
        #expect(target?.isTopFolder == false)
    }

    @Test func rootContainerIsTopFolder() {
        let target = ShortcutTarget.from(itemIdentifier: NSFileProviderItemIdentifier.rootContainer.rawValue,
                                         domain: "gdrive")
        #expect(target == ShortcutTarget(remote: "gdrive", path: ""))
        #expect(target?.isTopFolder == true)
    }

    @Test func identifierFromAnotherDomainIsRejected() {
        #expect(ShortcutTarget.from(itemIdentifier: "b2:Docs", domain: "b2-archive") == nil)
        #expect(ShortcutTarget.from(itemIdentifier: "Docs", domain: "b2") == nil)
        #expect(ShortcutTarget.from(itemIdentifier: "b2:Docs", domain: "") == nil)
    }

    @Test func remoteNamesWithColonsInPathsKeepThePath() {
        let target = ShortcutTarget.from(itemIdentifier: "s3:bucket/a:b.txt", domain: "s3")
        #expect(target?.path == "bucket/a:b.txt")
    }

    // MARK: - Messages

    @Test func backupRefusalsReadAsSentences() {
        #expect(ShortcutError.backup(.notApproved).message == "Preview this backup once in Nimbus before it can run.")
        #expect(ShortcutError.backup(.alreadyQueuedOrRunning).message == "This backup is already running.")
        #expect(ShortcutError.backup(.unknownJob).message == "That backup no longer exists.")
        #expect(ShortcutError.notInCloud(name: "a.txt").message == "“a.txt” isn't in a Nimbus cloud in Finder.")
    }

    @Test func runBackupDialog() {
        #expect(RunBackupIntent.startedMessage(name: "Docs", waiting: false) == "Started “Docs”.")
        #expect(RunBackupIntent.startedMessage(name: "Docs", waiting: true)
            == "“Docs” starts after the backup that's running.")
    }

    @Test func keepDownloadedDialog() {
        #expect(KeepDownloadedSupport.message(keep: true, count: 1) == "Keeping 1 item downloaded.")
        #expect(KeepDownloadedSupport.message(keep: false, count: 3) == "macOS may now remove the download of 3 items.")
    }

    // MARK: - Share link expiry

    @Test func s3LinksExpireAfterAWeekOthersNever() {
        #expect(CopyShareLinkIntent.expiry(forBackend: "s3") == .week)
        #expect(CopyShareLinkIntent.expiry(forBackend: "onedrive") == nil)
        #expect(CopyShareLinkIntent.expiry(forBackend: "drive") == nil)
    }

    // MARK: - Backup entities

    private func job(_ name: String) -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/\(name)"),
                                destination: .cloud(remote: "b2", path: name), now: Date())
        job.name = name
        return job
    }

    @Test func suggestedBackupsAreSortedByName() {
        let jobs = [job("Photos"), job("docs"), job("Code 10"), job("Code 9")]
        #expect(BackupEntityQuery.suggested(in: jobs).map(\.name) == ["Code 9", "Code 10", "docs", "Photos"])
    }

    @Test func entitiesForIdentifiersSkipDeletedBackups() {
        let docs = job("Docs")
        let found = BackupEntityQuery.entities(for: [UUID(), docs.id], in: [docs, job("Photos")])
        #expect(found.map(\.id) == [docs.id])
    }

    @Test func matchingFiltersByName() {
        let jobs = [job("Docs"), job("Photos"), job("Documents archive")]
        #expect(BackupEntityQuery.entities(matching: "doc", in: jobs).map(\.name) == ["Docs", "Documents archive"])
        #expect(BackupEntityQuery.entities(matching: "  ", in: jobs).count == 3)
    }

    @Test func entityShowsRoute() {
        let entity = BackupEntity(job: job("Docs"))
        #expect(entity.route.contains("→"))
    }

    // MARK: - Waiting for startup

    @Test @MainActor func waitThrowsAfterTimeout() async {
        await #expect(throws: ShortcutError.engineNotReady) {
            try await IntentServices.wait(until: { false }, or: .engineNotReady,
                                          timeout: .milliseconds(50), step: .milliseconds(10))
        }
    }

    @Test @MainActor func waitReturnsOnceReady() async throws {
        var calls = 0
        try await IntentServices.wait(until: { calls += 1; return calls > 2 }, or: .engineNotReady,
                                      timeout: .seconds(5), step: .milliseconds(1))
        #expect(calls == 3)
    }
}
