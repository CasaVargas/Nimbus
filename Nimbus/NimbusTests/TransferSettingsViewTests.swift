import Foundation
import SwiftUI
import Testing
@testable import Nimbus

@Suite("Transfer settings", .serialized)
@MainActor
struct TransferSettingsViewTests {
    @Test func rendersTransfersPane() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            TransferSettingsView(notifier: NotificationAuthorizationFixture(status: .authorized))
                .environment(settings())
                .environment(RcloneDaemon()),
            size: CGSize(width: 680, height: 640),
            named: "Settings-Transfers"
        )
    }

    @Test func rendersInvalidBandwidth() throws {
        let settings = settings()
        settings.bandwidthLimit = "10M"

        try SnapshotHelpers.assertHostedSnapshot(
            TransferSettingsView(
                notifier: NotificationAuthorizationFixture(status: .authorized),
                initialBandwidthLimitDraft: "10MB"
            )
            .environment(settings)
            .environment(RcloneDaemon()),
            size: CGSize(width: 680, height: 640),
            named: "Settings-Transfers-invalid-bandwidth"
        )
    }

    @Test func rendersNotificationsDenied() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            TransferSettingsView(
                notifier: NotificationAuthorizationFixture(status: .denied),
                initialNotificationAuthorizationStatus: .denied
            )
                .environment(settings())
                .environment(RcloneDaemon()),
            size: CGSize(width: 680, height: 640),
            named: "Settings-Transfers-notifications-denied"
        )
    }

    private func settings() -> AppSettings {
        let name = "NimbusTests.TransferSettings.\(UUID().uuidString)"
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
