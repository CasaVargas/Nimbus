import Testing
@testable import Nimbus

@Suite("RcloneDaemon settings")
@MainActor
struct RcloneDaemonSettingsTests {
    @Test func changingConfiguredPathRequiresRestart() {
        let daemon = makeConnectedDaemon(activePath: "/a/rclone")

        #expect(daemon.restartRequired(for: "/b/rclone"))
        #expect(!daemon.restartRequired(for: "/a/rclone"))
    }

    @Test func disconnectedDaemonDoesNotRequireRestart() {
        let daemon = RcloneDaemon()

        #expect(!daemon.restartRequired(for: "/b/rclone"))
    }

    private func makeConnectedDaemon(activePath: String) -> RcloneDaemon {
        RcloneDaemon(testStatus: .connected, activeBinaryPath: activePath)
    }
}
