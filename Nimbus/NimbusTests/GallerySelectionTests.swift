import Testing

@testable import Nimbus

@Suite("GallerySelection")
struct GallerySelectionTests {
    private let ids = ["a", "b", "c"]

    @Test func emptyFolderHasNoCurrentItem() {
        #expect(GallerySelection.current(selected: ["a"], in: []) == nil)
        #expect(GallerySelection.step(from: "a", by: 1, in: []) == nil)
    }

    @Test func nothingSelectedShowsTheFirstItem() {
        #expect(GallerySelection.current(selected: [], in: ids) == "a")
    }

    @Test func staleSelectionFallsBackToTheFirstItem() {
        #expect(GallerySelection.current(selected: ["gone"], in: ids) == "a")
        #expect(GallerySelection.step(from: "gone", by: 1, in: ids) == "a")
        #expect(GallerySelection.step(from: nil, by: -1, in: ids) == "a")
    }

    @Test func multiSelectionShowsTheEarliestInOrder() {
        #expect(GallerySelection.current(selected: ["c", "b"], in: ids) == "b")
    }

    @Test func stepsToNeighbours() {
        #expect(GallerySelection.step(from: "b", by: 1, in: ids) == "c")
        #expect(GallerySelection.step(from: "b", by: -1, in: ids) == "a")
    }

    @Test func stopsAtBothEnds() {
        #expect(GallerySelection.step(from: "a", by: -1, in: ids) == "a")
        #expect(GallerySelection.step(from: "c", by: 1, in: ids) == "c")
    }
}
