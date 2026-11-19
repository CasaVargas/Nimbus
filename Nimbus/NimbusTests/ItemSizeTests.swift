import Testing
@testable import Nimbus

@Suite("ItemSize")
struct ItemSizeTests {
    @Test func anUnknownSizeIsNotPassedOn() {
        // rclone lists Google Docs, Sheets and Slides with size -1; the
        // system showed that as Int64.max, which crashed Time Machine.
        #expect(ItemSize.documentSize(listed: -1) == nil)
        #expect(ItemSize.documentSize(listed: .min) == nil)
    }

    @Test func knownSizesArePassedOn() {
        #expect(ItemSize.documentSize(listed: 0) == 0)
        #expect(ItemSize.documentSize(listed: 39_520) == 39_520)
        #expect(ItemSize.documentSize(listed: .max) == .max)
    }

    @Test func anUnknownSizeMarksTheContentVersion() {
        // Placeholders the system already has keep their Int64.max size
        // unless the content version changes.
        #expect(ItemSize.contentVersionSuffix(listed: -1) == [1])
    }

    @Test func knownSizesLeaveTheContentVersionAlone() {
        // Every other item keeps the version it had, so nothing re-downloads.
        #expect(ItemSize.contentVersionSuffix(listed: 0) == [])
        #expect(ItemSize.contentVersionSuffix(listed: 39_520) == [])
    }
}
