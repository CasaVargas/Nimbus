import Testing
@testable import Nimbus

@Suite("Bandwidth limit validation")
struct BandwidthLimitValidatorTests {
    @Test(arguments: ["", "500", "100k", "10M", "2.5G", "1T"])
    func acceptsRcloneLimits(_ value: String) {
        #expect(BandwidthLimitValidator.validate(value))
    }

    @Test(arguments: ["abc", "10MB", "1t", "-5M"])
    func rejectsInvalidLimits(_ value: String) {
        #expect(!BandwidthLimitValidator.validate(value))
    }
}
