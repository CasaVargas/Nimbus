import Testing
@testable import Nimbus

@Suite("StorageQuota")
struct StorageQuotaTests {
    @Test func fractionIsNilWithoutTotal() {
        let q = StorageQuota(used: 412_000_000_000, total: nil)
        #expect(q.fraction == nil)
        #expect(q.free == nil)
        #expect(q.usedText != nil)
        #expect(q.totalText == nil)
        #expect(!q.isNearlyFull)
    }

    @Test func fractionAndFreeFromUsedAndTotal() {
        let q = StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000)
        #expect(abs((q.fraction ?? 0) - 0.64) < 0.0001)
        #expect(q.free == 720_000_000_000)
    }

    @Test func nearlyFullAbove90Percent() {
        #expect(StorageQuota(used: 911, total: 1000).isNearlyFull)
        #expect(!StorageQuota(used: 899, total: 1000).isNearlyFull)
    }

    @Test func fractionClampsOveruse() {
        #expect(StorageQuota(used: 1200, total: 1000).fraction == 1)
    }
}
