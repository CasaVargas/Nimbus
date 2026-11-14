import Foundation
import Testing
@testable import Nimbus

@Suite("AppSettings")
@MainActor
struct AppSettingsTests {
    private func isolatedDefaults() -> UserDefaults {
        let defaults = ScratchDefaults.make("AppSettings")
        return defaults
    }

    @Test func curatedDefaults() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.addNewRemotesToFinder)
        #expect(settings.newMountAccess == .readWrite)
        #expect(settings.newMountAutoMount == false)
        #expect(settings.defaultConflictPolicy == .rename)
        #expect(settings.transferNotificationMode == .failuresOnly)
        #expect(settings.transferHistoryRetention == .sevenDays)
        #expect(settings.bandwidthLimit.isEmpty)
        #expect(settings.concurrentTransfers == 4)
    }

    @Test func preferencesRoundTrip() {
        let defaults = isolatedDefaults()
        let first = AppSettings(defaults: defaults)
        first.newMountAccess = .readOnly
        first.transferHistoryRetention = .thirtyDays

        let second = AppSettings(defaults: defaults)

        #expect(second.newMountAccess == .readOnly)
        #expect(second.transferHistoryRetention == .thirtyDays)
    }
}
