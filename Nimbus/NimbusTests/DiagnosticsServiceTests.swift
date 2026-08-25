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

    @Test func diagnosticTextIncludesStrictNumericRcloneVersions() {
        let text = DiagnosticsService(info: fixtureInfo).systemInformation(
            daemon: RcloneDaemon(testStatus: .connected, rcloneVersion: "rclone v1.74.0")
        )
        let largeComponentText = DiagnosticsService(info: fixtureInfo).systemInformation(
            daemon: RcloneDaemon(testStatus: .connected, rcloneVersion: "rclone v12.0.345")
        )

        #expect(text.contains("rclone Version: v1.74.0"))
        #expect(largeComponentText.contains("rclone Version: v12.0.345"))
    }

    @Test(arguments: [
        "rclone v1.74.0 remoteName",
        "rclone v1.74.0-beta.1",
        "rclone v1.74.0+build.42",
        "rclone v1.74.0 malicious",
        "rclone v1.74.0; /Users/secret",
        "rclone v1.74",
        "rclone v1.74.0.1",
        "rclone v1.74.x",
        "not-rclone v1.74.0",
    ])
    func diagnosticTextRejectsNonSemanticRcloneVersion(_ version: String) {
        let text = DiagnosticsService(info: fixtureInfo).systemInformation(
            daemon: RcloneDaemon(testStatus: .connected, rcloneVersion: version)
        )

        #expect(text.contains("rclone Version: Unknown"))
        #expect(!text.contains(version))
    }

    private var fixtureInfo: DiagnosticsService.Info {
        .init(
            nimbusVersion: "1.0.0",
            buildNumber: "42",
            macOSVersion: "macOS 15.0",
            architecture: "arm64"
        )
    }
}
