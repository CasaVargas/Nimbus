import Foundation
import SwiftUI
import Testing
@testable import Nimbus

@Suite("Settings shell", .serialized)
@MainActor
struct SettingsViewTests {
    @Test func shellUsesThreeDestinations() {
        #expect(SettingsTab.allCases == [.general, .transfers, .advanced])
    }

    @Test func sceneRootAppliesLightAppearanceFromSettings() {
        let settings = settings()
        settings.appearance = .light
        let recorder = ColorSchemeRecorder()

        _ = SnapshotHelpers.renderHostedPNG(
            SceneAppearanceRoot(settings: settings) {
                ColorSchemeProbe(recorder: recorder)
            },
            size: CGSize(width: 40, height: 40)
        )

        #expect(recorder.colorScheme == .light)
    }

    @Test func rendersThreePaneShell() throws {
        let settings = settings()
        let daemon = RcloneDaemon(
            testStatus: .connected,
            activeBinaryPath: settings.rcloneBinaryPath,
            rcloneVersion: "rclone v1.74.0",
            port: 5572
        )
        let model = GeneralSettingsModel(
            cacheStore: SettingsCacheStoreFixture(bytes: 4_194_304),
            cacheUsage: .available(4_194_304)
        )

        try SnapshotHelpers.assertWindowSnapshot(
            SceneAppearanceRoot(settings: settings) {
                SettingsView(generalModel: model)
                    .environment(daemon)
                    .environment(LaunchAtLoginService(refreshOnInit: false))
                    .environment(BackgroundBackupsService(refreshOnInit: false))
                    .environment(\.transferNotifier, NotificationAuthorizationFixture(status: .authorized))
                    .environment(\.diagnosticsService, diagnosticsService)
            },
            contentSize: CGSize(width: 680, height: 520),
            configureWindow: { window in
                window.toolbarStyle = .preference
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
            },
            named: "Settings-Shell"
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

    private func settings() -> AppSettings {
        let defaults = ScratchDefaults.make("SettingsShell")
        return AppSettings(defaults: defaults)
    }
}

@MainActor
private final class ColorSchemeRecorder {
    var colorScheme: ColorScheme?
}

private struct ColorSchemeProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    let recorder: ColorSchemeRecorder

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task(id: colorScheme) {
                recorder.colorScheme = colorScheme
            }
    }
}

private actor NotificationAuthorizationFixture: TransferNotifying {
    private let status: NotificationAuthorizationStatus

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        status == .authorized
    }

    func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async {}
}

private struct SettingsCacheStoreFixture: LocalCacheManaging {
    let bytes: Int64

    func cachedBytes() async throws -> Int64 {
        bytes
    }

    func clearCache() async throws {}
}
