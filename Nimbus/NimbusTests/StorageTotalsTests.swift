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

    @Test func aPooledAccountsFreeSpaceIsLeftOut() {
        // A Google Workspace account reports its whole organisation's pool
        // (hundreds of TB) as its limit. Counting that as free space makes
        // every other cloud round to nothing.
        let personal = StorageQuota(used: 38 * gb, total: 215 * gb)
        let pooled = StorageQuota(used: 23 * gb, total: 424_300 * gb)
        let totals = StorageTotals(quotas: [personal, pooled])
        #expect(totals.usedBytes == 61 * gb)
        #expect(totals.freeBytes == 177 * gb)
        // The pooled account widens the bar only by what it uses, the same
        // as pay-as-you-go storage.
        #expect(totals.capacityBytes == 238 * gb)
    }

    @Test func aLargePersonalPlanStillCounts() {
        // 30 TB is the biggest consumer plan around; it must not be mistaken
        // for a pool.
        let totals = StorageTotals(quotas: [StorageQuota(used: 1_000 * gb, total: 30_000 * gb)])
        #expect(totals.freeBytes == 29_000 * gb)
        #expect(totals.capacityBytes == 30_000 * gb)
    }

    @Test func onlyPooledAccountsMeansNoFreeFigure() {
        let totals = StorageTotals(quotas: [StorageQuota(used: 23 * gb, total: 424_300 * gb)])
        #expect(totals.freeBytes == nil)
        #expect(totals.capacityBytes == 23 * gb)
    }

    @Test func shareIsACloudsUsageOverTheWholeBar() {
        let personal = StorageQuota(used: 1_000 * gb, total: 2_000 * gb)
        let totals = StorageTotals(quotas: [personal, StorageQuota(used: 0, total: 2_000 * gb)])
        #expect(totals.share(of: personal) == 0.25)
        #expect(totals.usedFraction == 0.25)
    }
}
