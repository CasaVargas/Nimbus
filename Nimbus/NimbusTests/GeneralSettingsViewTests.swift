import Foundation
import SwiftUI
import Testing
@testable import Nimbus

@Suite("General settings", .serialized)
@MainActor
struct GeneralSettingsViewTests {
    @Test func rendersGeneralPane() throws {
        let model = GeneralSettingsModel(
            cacheStore: CacheStoreFixture(bytes: 4_194_304),
            cacheUsage: .available(4_194_304)
        )
        try SnapshotHelpers.assertHostedSnapshot(
            GeneralSettingsView(model: model)
                .environment(AppSettings(defaults: isolatedDefaults()))
                .environment(LaunchAtLoginService()),
            size: CGSize(width: 680, height: 450),
            named: "Settings-General"
        )
    }

    @Test func rendersCacheFailure() throws {
        let model = GeneralSettingsModel(
            cacheStore: CacheStoreFixture(error: "Cache folder is unavailable."),
            cacheUsage: .failed("Cache folder is unavailable.")
        )
        try SnapshotHelpers.assertHostedSnapshot(
            GeneralSettingsView(model: model)
                .environment(AppSettings(defaults: isolatedDefaults()))
                .environment(LaunchAtLoginService()),
            size: CGSize(width: 680, height: 450),
            named: "Settings-General-cache-error"
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "NimbusTests.GeneralSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private struct CacheStoreFixture: LocalCacheManaging {
    let bytes: Int64?
    let error: String?

    init(bytes: Int64) {
        self.bytes = bytes
        error = nil
    }

    init(error: String) {
        bytes = nil
        self.error = error
    }

    func cachedBytes() async throws -> Int64 {
        if let error {
            throw CacheStoreFixtureError(message: error)
        }
        return bytes ?? 0
    }

    func clearCache() async throws {}
}

private struct CacheStoreFixtureError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
