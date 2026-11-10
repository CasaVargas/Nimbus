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

    @Test func alertCopyIsTheSpecs() {
        #expect(QuitDecision.alertMessage
            == "A backup is running. If you quit, it stops and runs again the next time Nimbus opens.")
    }
}
