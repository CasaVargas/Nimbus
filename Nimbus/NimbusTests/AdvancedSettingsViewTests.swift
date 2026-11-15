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
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)),
                encryptionModel: Self.fixedSignIns
            )
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: Self.fullHeight,
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
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(
                    cacheUsage: .failed("Nimbus couldn't read its Finder change records.")),
                encryptionModel: Self.fixedSignIns
            )
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: Self.fullHeight,
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
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)),
                encryptionModel: Self.fixedSignIns
            )
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: Self.fullHeight,
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
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)),
                encryptionModel: Self.fixedSignIns
            )
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: Self.fullHeight,
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
            AdvancedSettingsView(
                storageModel: GeneralSettingsModel(cacheUsage: .available(4_194_304)),
                encryptionModel: Self.fixedSignIns
            )
                .environment(settings)
                .environment(daemon)
                .environment(\.diagnosticsService, diagnosticsService),
            size: Self.fullHeight,
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

    /// Tall enough that the whole pane fits. When it doesn't, the pane
    /// scrolls, and a Mac set to always show scroll bars (a CI runner has
    /// no trackpad) draws one and re-wraps the text beside it, while a Mac
    /// with overlay scroll bars doesn't. 820 fit until the descriptions
    /// went from 10pt to 12pt.
    private static let fullHeight = CGSize(width: 680, height: 1100)

    /// The saved sign-ins section reads this Mac's rclone config unless it
    /// is told not to. These snapshots aren't about that section, so pin
    /// it: otherwise the render differs between a Mac with a config and a
    /// CI runner without one.
    private static var fixedSignIns: ConfigEncryptionModel {
        ConfigEncryptionModel(state: .plain, readsLiveState: false)
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
