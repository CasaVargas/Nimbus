import Foundation
import Testing
@testable import Nimbus

@Suite("Quit guard")
struct QuitGuardTests {
    @Test func quitAsksOnlyWhileRunning() {
        #expect(QuitDecision.make(isBackupRunning: true, isPowerOff: false) == .askFirst)
        #expect(QuitDecision.make(isBackupRunning: false, isPowerOff: false) == .quit)
    }

    @Test func logoutAndRestartSkipTheAlert() {
        #expect(QuitDecision.make(isBackupRunning: true, isPowerOff: true) == .quit)
        #expect(QuitDecision.make(isBackupRunning: false, isPowerOff: true) == .quit)
    }

    static let specSentence = "A backup is running. If you quit, it stops and runs again the next time Nimbus opens."
    static let shortSentence = "A backup is running. If you quit, it stops."

    /// The alert for quitting while `jobs` are running or queued.
    private func message(_ jobs: [BackupJob]) -> String {
        QuitDecision.alertMessage(runsAgain: QuitDecision.runsAgain(interrupting: jobs))
    }

    private func job(_ schedule: BackupSchedule, paused: Bool = false) -> BackupJob {
        var job = BackupJobTests.job()
        job.schedule = schedule
        job.isPaused = paused
        return job
    }

    @Test func scheduledJobRunningKeepsTheSpecsSentence() {
        #expect(message([job(.daily(hour: 2, minute: 0))]) == Self.specSentence)
        #expect(message([job(.hourly)]) == Self.specSentence)
    }

    @Test func manualJobRunningSaysOnlyThatItStops() {
        #expect(message([job(.manual)]) == Self.shortSentence)
        // A paused job's schedule doesn't run it again either.
        #expect(message([job(.weekly(weekday: 2, hour: 9, minute: 0), paused: true)]) == Self.shortSentence)
    }

    @Test func manualRunningWithScheduledQueuedKeepsTheSpecsSentence() {
        #expect(message([job(.manual), job(.daily(hour: 2, minute: 0))]) == Self.specSentence)
    }
}

@Suite("Notification click buffer")
struct NotificationClickBufferTests {
    @Test func clicksBeforeTheHandlerExistAreReplayedOnce() {
        var buffer = NotificationClickBuffer()
        let id = UUID()
        buffer.receive(id, handler: nil)
        buffer.receive(nil, handler: nil)
        var got: [UUID?] = []
        buffer.flush { got.append($0) }
        #expect(got == [id, nil])
        buffer.flush { got.append($0) }
        #expect(got.count == 2)
    }

    @Test func clicksWithAHandlerAreNotBuffered() {
        var buffer = NotificationClickBuffer()
        var got: [UUID?] = []
        let id = UUID()
        buffer.receive(id, handler: { got.append($0) })
        buffer.flush { got.append($0) }
        #expect(got == [id])
    }
}
