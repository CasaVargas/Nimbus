import Foundation
import Testing
@testable import Nimbus
import RcloneKit

@Suite("Transfer runtime settings", .serialized)
@MainActor
struct TransferRuntimeSettingsTests {
    @Test func persistsUnlimitedBandwidthOnlyAfterRcloneAcceptsOff() async throws {
        let settings = makeSettings()
        settings.bandwidthLimit = "10M"
        let runtime = RecordingTransferRuntime()

        try await TransferRuntimeSettings.applyBandwidthLimit(
            "",
            settings: settings,
            runtime: runtime
        )

        #expect(runtime.bandwidthRates == ["off"])
        #expect(settings.bandwidthLimit.isEmpty)
    }

    @Test func keepsPersistedBandwidthWhenRcloneRejectsChange() async {
        let settings = makeSettings()
        settings.bandwidthLimit = "10M"
        let runtime = RecordingTransferRuntime(error: FixtureError.rejected)

        await #expect(throws: FixtureError.rejected) {
            try await TransferRuntimeSettings.applyBandwidthLimit(
                "20M",
                settings: settings,
                runtime: runtime
            )
        }

        #expect(settings.bandwidthLimit == "10M")
    }

    @Test func persistsConcurrentTransfersOnlyAfterLiveOptionsSetSucceeds() async throws {
        let settings = makeSettings()
        let runtime = RecordingTransferRuntime()

        try await TransferRuntimeSettings.applyConcurrentTransfers(
            7,
            settings: settings,
            runtime: runtime
        )

        #expect(runtime.concurrentTransferCounts == [7])
        #expect(settings.concurrentTransfers == 7)
    }

    @Test func keepsPersistedConcurrentTransfersWhenRcloneRejectsChange() async {
        let settings = makeSettings()
        settings.concurrentTransfers = 4
        let runtime = RecordingTransferRuntime(error: FixtureError.rejected)

        await #expect(throws: FixtureError.rejected) {
            try await TransferRuntimeSettings.applyConcurrentTransfers(
                9,
                settings: settings,
                runtime: runtime
            )
        }

        #expect(settings.concurrentTransfers == 4)
    }

    private func makeSettings() -> AppSettings {
        let name = "NimbusTests.TransferRuntimeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
    }
}

private enum FixtureError: Error, Equatable {
    case rejected
}

private final class RecordingTransferRuntime: TransferRuntimeConfiguring {
    private let error: Error?
    private(set) var bandwidthRates: [String] = []
    private(set) var concurrentTransferCounts: [Int] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func setBandwidthLimit(rate: String) async throws -> BandwidthLimitResponse {
        if let error { throw error }
        bandwidthRates.append(rate)
        return try JSONDecoder().decode(
            BandwidthLimitResponse.self,
            from: Data("""
            {"bytesPerSecond":-1,"bytesPerSecondTx":-1,"bytesPerSecondRx":-1,"rate":"\(rate)"}
            """.utf8)
        )
    }

    func setConcurrentTransfers(_ transfers: Int) async throws {
        if let error { throw error }
        concurrentTransferCounts.append(transfers)
    }
}
