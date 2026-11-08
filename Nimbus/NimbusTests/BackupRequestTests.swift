import Foundation
import Testing
import RcloneKit
@testable import Nimbus

struct BackupRequestTests {
    static let stamp = "2026-11-08 160000"

    static func job(_ mutate: (inout BackupJob) -> Void = { _ in }) -> BackupJob {
        var job = BackupJob.new(
            source: .local(path: "/Users/j/Documents"),
            destination: .cloud(remote: "b2", path: "mac/Docs"),
            now: Date(timeIntervalSince1970: 0)
        )
        job.excludes = [".DS_Store"]
        mutate(&job)
        return job
    }

    @Test func mirrorWithVersionsInside() {
        let request = BackupRequest.make(job: Self.job(), dryRun: false, stamp: Self.stamp)
        #expect(request.operation == .sync)
        #expect(request.srcFs == "/Users/j/Documents")
        #expect(request.dstFs == "b2:mac/Docs")
        #expect(request.excludeRules == [".DS_Store", "/.nimbus-versions/**"])
        #expect(request.backupDir == "b2:mac/Docs/.nimbus-versions/2026-11-08 160000")
        #expect(request.maxDelete == 100)
        #expect(request.dryRun == false)
        #expect(request.reports.isEmpty)
    }

    @Test func addOnlyHasNoMaxDeleteAndNoMissingOnSrc() {
        let request = BackupRequest.make(job: Self.job { $0.mode = .addOnly }, dryRun: true, stamp: Self.stamp)
        #expect(request.operation == .copy)
        #expect(request.maxDelete == nil)
        #expect(request.dryRun == true)
        #expect(request.reports == [.missingOnDst, .differ, .error])
    }

    @Test func mirrorPreviewRequestsAllFourReports() {
        let request = BackupRequest.make(job: Self.job(), dryRun: true, stamp: Self.stamp)
        #expect(request.reports == [.missingOnDst, .missingOnSrc, .differ, .error])
        #expect(request.maxDelete == 100)
        #expect(request.backupDir == "b2:mac/Docs/.nimbus-versions/2026-11-08 160000")
    }

    @Test func versionsOffHasNoBackupDirAndNoVersionsExclude() {
        let request = BackupRequest.make(job: Self.job { $0.versions.enabled = false }, dryRun: false, stamp: Self.stamp)
        #expect(request.backupDir == nil)
        #expect(request.excludeRules == [".DS_Store"])
    }

    @Test func customVersionsLocationIsNotExcluded() {
        let job = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "old")) }
        let request = BackupRequest.make(job: job, dryRun: false, stamp: Self.stamp)
        #expect(request.backupDir == "b2:old/2026-11-08 160000")
        #expect(request.excludeRules == [".DS_Store"])
    }

    @Test func noRemovalLimitMeansNoMaxDelete() {
        let request = BackupRequest.make(job: Self.job { $0.removalLimit = nil }, dryRun: false, stamp: Self.stamp)
        #expect(request.maxDelete == nil)
    }

    @Test func stampFormat() {
        let date = ISO8601DateFormatter().date(from: "2026-11-08T21:00:00Z")!
        #expect(BackupRequest.stamp(for: date, timeZone: TimeZone(identifier: "America/New_York")!) == "2026-11-08 160000")
    }

    @Test func cliForAwkwardPath() {
        let job = Self.job { $0.source = .local(path: "/Users/j/Résumé \"final\" it's") }
        let cli = BackupRequest.cliCommand(job: job)
        #expect(cli.contains(#"'/Users/j/Résumé "final" it'\''s'"#))
    }

    @Test func cliMirrorSnapshot() {
        #expect(BackupRequest.cliCommand(job: Self.job()) ==
            #"rclone sync '/Users/j/Documents' 'b2:mac/Docs' --exclude '.DS_Store' --exclude '/.nimbus-versions/**' --backup-dir 'b2:mac/Docs/.nimbus-versions/'"$(date +'%Y-%m-%d %H%M%S')" --max-delete 100"#)
    }

    @Test func cliAddOnlySnapshot() {
        let job = Self.job {
            $0.mode = .addOnly
            $0.versions.enabled = false
            $0.excludes = []
        }
        #expect(BackupRequest.cliCommand(job: job) == "rclone copy '/Users/j/Documents' 'b2:mac/Docs'")
    }
}
