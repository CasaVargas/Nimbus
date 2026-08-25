import Testing
@testable import Nimbus

@Suite("DiagnosticsService")
@MainActor
struct DiagnosticsServiceTests {
    @Test func diagnosticTextExcludesUserData() {
        let daemon = RcloneDaemon(
            testStatus: .error("remoteName failed at /Users/secret/Documents"),
            activeBinaryPath: "/Users/secret/bin/rclone",
            rcloneVersion: "rclone v1.74.0 remoteName /Users/secret"
        )
        let service = DiagnosticsService(
            info: .init(
                nimbusVersion: "1.0.0",
                buildNumber: "42",
                macOSVersion: "macOS 15.0",
                architecture: "arm64"
            )
        )

        let text = service.systemInformation(daemon: daemon)

        #expect(text.contains("Nimbus Version: 1.0.0 (42)"))
        #expect(text.contains("macOS Version: macOS 15.0"))
        #expect(text.contains("Architecture: arm64"))
        #expect(text.contains("rclone Version: Unknown"))
        #expect(text.contains("Daemon Status: Error"))
        #expect(text.contains("Daemon Port: 5572"))
        #expect(!text.contains("remoteName"))
        #expect(!text.contains("/Users/"))
    }
}
