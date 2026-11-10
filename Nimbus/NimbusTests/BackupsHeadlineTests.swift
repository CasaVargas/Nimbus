import Testing
import Foundation
@testable import Nimbus

@Suite("BackupsHeadline")
struct BackupsHeadlineTests {
    private func status(_ tint: BackupStatus.Tint, running: Bool = false) -> BackupStatus {
        BackupStatus(sentence: "", tint: tint, progress: running ? 0.4 : nil)
    }

    @Test func everyBackupFinishedReadsAsAllUpToDate() {
        let h = BackupsHeadline(statuses: [status(.ok), status(.ok), status(.ok)])
        #expect(h.title == "All 3 backups are up to date")
        #expect(h.sentence == nil)
        #expect(h.tone == .ok)
    }

    @Test func oneBackupIsNotCalledAll() {
        #expect(BackupsHeadline(statuses: [status(.ok)]).title == "Your backup is up to date")
    }

    @Test func aFailedOrBlockedBackupIsCountedAndCalledOut() {
        let h = BackupsHeadline(statuses: [status(.ok), status(.error), status(.warning)])
        #expect(h.title == "1 of 3 backups is up to date")
        #expect(h.sentence == "2 need a look.")
        #expect(h.tone == .warning)
    }

    @Test func aRunningBackupIsMentionedFirst() {
        let h = BackupsHeadline(statuses: [status(.ok), status(.info, running: true)])
        #expect(h.title == "1 of 2 backups is up to date")
        #expect(h.sentence == "1 is running now.")
        #expect(h.tone == .neutral)
    }

    @Test func runningAndAttentionAreBothSaid() {
        let h = BackupsHeadline(statuses: [status(.info, running: true), status(.error)])
        #expect(h.sentence == "1 is running now. 1 needs a look.")
        #expect(h.tone == .warning)
    }

    @Test func backupsThatHaveNeverRunAreNotUpToDate() {
        let h = BackupsHeadline(statuses: [status(.secondary), status(.secondary)])
        #expect(h.title == "0 of 2 backups are up to date")
        #expect(h.sentence == nil)
        #expect(h.tone == .neutral)
    }
}
