import Foundation
import SwiftUI
import Testing
@testable import Nimbus

@Suite("General settings", .serialized)
@MainActor
struct GeneralSettingsViewTests {
    @Test func clearCacheFailureReportsErrorWithoutSuccessUsage() async {
        let model = GeneralSettingsModel(
            cacheStore: CacheStoreFixture(clearError: "Sync data could not be cleared."),
            cacheUsage: .available(4_194_304)
        )

        await model.clearCache()

        #expect(model.cacheUsage == .failed("Sync data could not be cleared."))
        #expect(model.clearCacheError == "Sync data could not be cleared.")
        #expect(!model.isClearingCache)
    }

    @Test func rendersGeneralPane() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            GeneralSettingsView()
                .environment(AppSettings(defaults: isolatedDefaults()))
                .environment(LaunchAtLoginService(refreshOnInit: false))
                .preferredColorScheme(.dark),
            size: CGSize(width: 680, height: 520),
            named: "Settings-General"
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
    let clearError: String?

    init(bytes: Int64) {
        self.bytes = bytes
        error = nil
        clearError = nil
    }

    init(error: String) {
        bytes = nil
        self.error = error
        clearError = nil
    }

    init(clearError: String) {
        bytes = nil
        error = nil
        self.clearError = clearError
    }

    func cachedBytes() async throws -> Int64 {
        if let error {
            throw CacheStoreFixtureError(message: error)
        }
        return bytes ?? 0
    }

    func clearCache() async throws {
        if let clearError {
            throw CacheStoreFixtureError(message: clearError)
        }
    }
}

private struct CacheStoreFixtureError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
