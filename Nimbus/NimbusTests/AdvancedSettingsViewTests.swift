import Foundation
import SwiftUI
import Testing
@testable import Nimbus

@Suite("Advanced settings", .serialized)
@MainActor
struct AdvancedSettingsViewTests {
    @Test func rendersAdvancedConnected() throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .connected,
            activeBinaryPath: "/opt/homebrew/bin/rclone",
            rcloneVersion: "rclone v1.74.0",
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 450),
            named: "Settings-Advanced-connected"
        )
    }

    @Test func rendersRestartRequiredState() throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .connected,
            activeBinaryPath: "/usr/local/bin/rclone",
            rcloneVersion: "rclone v1.74.0",
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 450),
            named: "Settings-Advanced-restart-required"
        )
    }

    @Test func rendersDisconnectedState() throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .idle,
            activeBinaryPath: nil,
            rcloneVersion: nil,
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 450),
            named: "Settings-Advanced-disconnected"
        )
    }

    @Test func rendersDaemonErrorState() throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .error("Failed to start rclone: The file doesn't exist."),
            activeBinaryPath: nil,
            rcloneVersion: nil,
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView()
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 450),
            named: "Settings-Advanced-error"
        )
    }

    private var diagnosticsService: DiagnosticsService {
        DiagnosticsService(
            info: .init(
                nimbusVersion: "1.0.0",
                buildNumber: "42",
                macOSVersion: "macOS 15.0",
                architecture: "arm64"
            )
        )
    }

    private func settings(path: String) -> AppSettings {
        let name = "NimbusTests.AdvancedSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(path, forKey: "rcloneBinaryPath")
        return AppSettings(defaults: defaults)
    }
}
