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

        try SnapshotHelpers.assertHostedSnapshot(
            SettingsView(generalModel: model)
                .environment(settings)
                .environment(daemon)
                .environment(LaunchAtLoginService(refreshOnInit: false))
                .environment(\.transferNotifier, NotificationAuthorizationFixture(status: .authorized))
                .environment(\.diagnosticsService, diagnosticsService),
            size: CGSize(width: 680, height: 520),
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
        let name = "NimbusTests.SettingsShell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
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
