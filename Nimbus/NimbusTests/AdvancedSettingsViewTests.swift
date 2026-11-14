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
            AdvancedSettingsView(storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)))
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 820),
            named: "Settings-Advanced-connected"
        )
    }

    @Test func rendersFinderRecordsFailure() throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .connected,
            activeBinaryPath: "/opt/homebrew/bin/rclone",
            rcloneVersion: "rclone v1.74.0",
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView(storageModel: GeneralSettingsModel(
                cacheUsage: .failed("Nimbus couldn't read its Finder change records.")))
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 820),
            named: "Settings-Advanced-records-error"
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
            AdvancedSettingsView(storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)))
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 820),
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
            AdvancedSettingsView(storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)))
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 820),
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
            AdvancedSettingsView(storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)))
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 820),
            named: "Settings-Advanced-error"
        )
    }

    @Test(arguments: [
        (ConfigEncryptionState.plain, "Settings-Advanced-signins-plain"),
        (ConfigEncryptionState.locked, "Settings-Advanced-signins-locked"),
        (ConfigEncryptionState.lockedWithoutKey, "Settings-Advanced-signins-no-key"),
    ])
    func rendersSavedSignIns(state: ConfigEncryptionState, name: String) throws {
        let settings = settings(path: "/opt/homebrew/bin/rclone")
        let daemon = RcloneDaemon(
            testStatus: .connected,
            activeBinaryPath: "/opt/homebrew/bin/rclone",
            rcloneVersion: "rclone v1.76.0",
            port: 5572
        )

        try SnapshotHelpers.assertHostedSnapshot(
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)),
                encryptionModel: ConfigEncryptionModel(state: state, readsLiveState: false)
            )
            .environment(settings)
            .environment(daemon)
            .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 1100),
            named: name
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
        let defaults = ScratchDefaults.make("AdvancedSettings")
        defaults.set(path, forKey: "rcloneBinaryPath")
        return AppSettings(defaults: defaults)
    }
}
