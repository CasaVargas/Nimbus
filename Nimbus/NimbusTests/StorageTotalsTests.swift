import Testing
import Foundation
@testable import Nimbus

@Suite("StorageTotals")
struct StorageTotalsTests {
    private let gb: Int64 = 1_000_000_000

    @Test func sumsLimitedAndPayAsYouGoClouds() {
        let totals = StorageTotals(quotas: [
            StorageQuota(used: 1_280 * gb, total: 2_000 * gb),
            StorageQuota(used: 412 * gb, total: 1_000 * gb),
            StorageQuota(used: 61 * gb, total: 2_000 * gb),
            StorageQuota(used: 720 * gb, total: nil),
        ])
        #expect(totals.usedBytes == 2_473 * gb)
        // Free space only counts clouds with a limit.
        #expect(totals.freeBytes == 3_247 * gb)
        // A cloud without a limit widens the bar by what it uses.
        #expect(totals.capacityBytes == 5_720 * gb)
    }

    @Test func freeIsUnknownWhenNoCloudReportsALimit() {
        let totals = StorageTotals(quotas: [StorageQuota(used: 720 * gb, total: nil)])
        #expect(totals.freeBytes == nil)
        #expect(totals.capacityBytes == 720 * gb)
    }

    @Test func nothingKnownMeansNoFractions() {
        let totals = StorageTotals(quotas: [])
        #expect(totals.usedFraction == nil)
        #expect(totals.share(of: StorageQuota(used: 5, total: 10)) == 0)
    }

    @Test func shareIsACloudsUsageOverTheWholeBar() {
        let personal = StorageQuota(used: 1_000 * gb, total: 2_000 * gb)
        let totals = StorageTotals(quotas: [personal, StorageQuota(used: 0, total: 2_000 * gb)])
        #expect(totals.share(of: personal) == 0.25)
        #expect(totals.usedFraction == 0.25)
    }
}
