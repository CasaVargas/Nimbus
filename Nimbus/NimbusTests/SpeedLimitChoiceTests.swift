import Testing
@testable import Nimbus

@Suite("SpeedLimitChoice")
struct SpeedLimitChoiceTests {
    @Test func presetsRoundTrip() throws {
        for choice in SpeedLimitChoice.presets {
            let value = try #require(choice.value)
            #expect(SpeedLimitChoice(storedValue: value) == choice)
        }
    }

    @Test func emptyAndWhitespaceMeanNoLimit() {
        #expect(SpeedLimitChoice(storedValue: "") == .unlimited)
        #expect(SpeedLimitChoice(storedValue: "  ") == .unlimited)
    }

    @Test func anythingElseIsCustom() {
        for value in ["2.5M", "500k", "1G", "5m", "7M"] {
            #expect(SpeedLimitChoice(storedValue: value) == .custom)
        }
        #expect(SpeedLimitChoice.custom.value == nil)
    }

    @Test func presetValuesAreValidRcloneLimits() {
        for choice in SpeedLimitChoice.presets {
            #expect(BandwidthLimitValidator.validate(choice.value ?? "x"))
        }
    }
}
