import Testing
import Foundation
@testable import Nimbus

@Suite("HomeHeadline")
struct HomeHeadlineTests {
    private let gb: Int64 = 1_000_000_000

    private func row(_ name: String, _ health: CloudSummary.Health = .ready,
                     used: Int64?, total: Int64?) -> CloudSummary.Row {
        .init(id: name, providerType: "drive", providerName: "Google Drive", health: health, sentence: "Ready",
              quota: used.map { StorageQuota(used: $0, total: total) }, isInFinder: true,
              tint: 0, lastConnected: nil, errorDetail: nil)
    }

    private func summary(_ rows: [CloudSummary.Row], overall: CloudSummary.Overall = .allReady) -> CloudSummary {
        let totals = StorageTotals(quotas: rows.compactMap(\.quota))
        return CloudSummary(rows: rows, overall: overall, attention: nil, suggestions: [],
                            usedBytes: totals.usedBytes, freeBytes: totals.freeBytes,
                            capacityBytes: totals.capacityBytes)
    }

    @Test func leadsWithFreeSpaceWhenAnyCloudHasALimit() {
        let s = summary([row("Personal", used: 1_280 * gb, total: 2_000 * gb), row("Archive", used: 720 * gb, total: nil)])
        #expect(HomeHeadline.title(for: s) == "\(ByteText.format(720 * gb)) free")
        #expect(HomeHeadline.sentence(for: s)
                == "\(ByteText.format(2_000 * gb)) used across 2 clouds. Everything is ready.")
    }

    @Test func leadsWithUsageWhenNothingHasALimit() {
        // Pay-as-you-go storage has no "free", so the headline never invents one.
        let s = summary([row("Archive", used: 720 * gb, total: nil)])
        #expect(HomeHeadline.title(for: s) == "\(ByteText.format(720 * gb)) used")
        #expect(HomeHeadline.sentence(for: s) == "Across 1 cloud. Everything is ready.")
    }

    @Test func countsCloudsWhileStorageIsUnknown() {
        let s = summary([row("Personal", .checking, used: nil, total: nil), row("Work", .checking, used: nil, total: nil)])
        #expect(HomeHeadline.title(for: s) == "2 clouds")
        #expect(HomeHeadline.sentence(for: s) == "Everything is ready.")
    }

    @Test func saysWhatNeedsAttentionInTheMenuBarsWords() {
        let work = row("Work", .needsSignIn, used: 412 * gb, total: 1_000 * gb)
        let s = summary([work], overall: .needsAttention(work))
        #expect(HomeHeadline.sentence(for: s).hasSuffix("Work needs you to sign in."))
    }

    @Test func aSentenceThatAlreadyEndsInPunctuationIsNotDoubled() {
        let busy = CloudSummary.Busy(progress: 0.3, sentence: "Copying 3 items to Dropbox…", direction: .up,
                                     focusCloud: "Dropbox", eta: nil)
        let s = summary([row("Dropbox", .busy, used: nil, total: nil)], overall: .busy(busy))
        #expect(HomeHeadline.sentence(for: s) == "Copying 3 items to Dropbox…")
    }

    @Test func cardStatusKeepsNumbersWithTheirUnits() {
        let nbsp = "\u{00A0}"
        #expect(HomeCloudCard.keepingNumbersWithUnits("Uploading 3 items, 2 min left")
            == "Uploading 3\(nbsp)items, 2\(nbsp)min left")
        #expect(HomeCloudCard.keepingNumbersWithUnits("Ready") == "Ready")
        #expect(HomeCloudCard.keepingNumbersWithUnits("Last connected 2 days ago.") == "Last connected 2\(nbsp)days ago.")
    }
}
