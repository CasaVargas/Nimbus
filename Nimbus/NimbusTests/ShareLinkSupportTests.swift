import Testing
@testable import Nimbus

@Suite("ShareLinkSupport")
struct ShareLinkSupportTests {
    @Test func s3LinksAlwaysExpireWithinAWeek() {
        let support = ShareLinkSupport.forBackend("s3")
        #expect(support.expiryChoices == [.day, .week])
        #expect(support.defaultExpiry == .week)
        #expect(!support.canStopSharing)
    }

    @Test(arguments: ["onedrive", "filescom", "pikpak", "storj", "dosya"])
    func servicesThatHonourExpiryOfferEveryChoice(backend: String) {
        let support = ShareLinkSupport.forBackend(backend)
        #expect(support.expiryChoices == [.never, .day, .week, .month])
        #expect(support.defaultExpiry == .never)
        #expect(!support.canStopSharing)
    }

    /// rclone 1.76 ignores both `expire` and `unlink` for these, and an
    /// ignored `unlink` makes a new link instead of removing one.
    @Test(arguments: ["drive", "dropbox", "pcloud", "b2", "box", "mega", "sftp", "", "something-new"])
    func servicesThatIgnoreBothGetNeitherControl(backend: String) {
        let support = ShareLinkSupport.forBackend(backend)
        #expect(support.expiryChoices.isEmpty)
        #expect(!support.canStopSharing)
    }

    @Test(arguments: ["jottacloud", "pixeldrain", "yandex"])
    func servicesThatOnlyUnlink(backend: String) {
        let support = ShareLinkSupport.forBackend(backend)
        #expect(support.expiryChoices.isEmpty)
        #expect(support.canStopSharing)
    }

    @Test(arguments: ["gofile", "kdrive"])
    func servicesWithBoth(backend: String) {
        let support = ShareLinkSupport.forBackend(backend)
        #expect(support.expiryChoices == [.never, .day, .week, .month])
        #expect(support.canStopSharing)
    }

    @Test func durationsAreRcloneDurations() {
        #expect(ShareLinkSupport.Expiry.never.duration == nil)
        #expect(ShareLinkSupport.Expiry.day.duration == "1d")
        #expect(ShareLinkSupport.Expiry.week.duration == "7d")
        #expect(ShareLinkSupport.Expiry.month.duration == "30d")
    }

    @Test func copiedCaptionNamesTheExpiry() {
        #expect(ShareLinkSupport.copiedCaption(expiry: nil) == "Link copied.")
        #expect(ShareLinkSupport.copiedCaption(expiry: .never) == "Link copied.")
        #expect(ShareLinkSupport.copiedCaption(expiry: .day) == "Link copied. It stops working after 1 day.")
        #expect(ShareLinkSupport.copiedCaption(expiry: .month) == "Link copied. It stops working after 30 days.")
    }
}
