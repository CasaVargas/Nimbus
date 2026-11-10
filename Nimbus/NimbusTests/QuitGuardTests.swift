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

    @Test func alertCopyIsTheSpecs() {
        #expect(QuitDecision.alertMessage
            == "A backup is running. If you quit, it stops and runs again the next time Nimbus opens.")
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
