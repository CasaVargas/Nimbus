import Testing
@testable import Nimbus

@Suite("Selection")
@MainActor
struct SelectionTests {
    let order = ["a", "b", "c", "d", "e"]

    @Test func plainSelectReplacesAndSetsAnchor() {
        let sel = Selection<String>()
        sel.select("c", in: order)
        #expect(sel.ids == ["c"])
        #expect(sel.anchor == "c")
    }

    @Test func toggleAddsAndRemoves() {
        let sel = Selection<String>()
        sel.select("a", in: order)
        sel.toggle("c")
        #expect(sel.ids == ["a", "c"])
        sel.toggle("a")
        #expect(sel.ids == ["c"])
    }

    @Test func extendFromAnchorSelectsRangeInclusive() {
        let sel = Selection<String>()
        sel.select("b", in: order)
        sel.extend(to: "d", in: order)
        #expect(sel.ids == ["b", "c", "d"])
        #expect(sel.anchor == "b") // anchor doesn't move on extend
    }

    @Test func extendBackwardWorks() {
        let sel = Selection<String>()
        sel.select("d", in: order)
        sel.extend(to: "b", in: order)
        #expect(sel.ids == ["b", "c", "d"])
    }

    @Test func extendWithoutAnchorBecomesSelect() {
        let sel = Selection<String>()
        sel.extend(to: "c", in: order)
        #expect(sel.ids == ["c"])
        #expect(sel.anchor == "c")
    }

    @Test func clearRemovesAllAndAnchor() {
        let sel = Selection<String>()
        sel.select("a", in: order)
        sel.toggle("b")
        sel.clear()
        #expect(sel.ids.isEmpty)
        #expect(sel.anchor == nil)
    }

    @Test func replaceWithSetSetsAnchorToFirstOrderedMember() {
        let sel = Selection<String>()
        sel.replace(with: ["c", "a"], in: order)
        #expect(sel.ids == ["a", "c"])
        #expect(sel.anchor == "a")
    }

    @Test func extendIgnoresIDsNotInOrdering() {
        let sel = Selection<String>()
        sel.select("a", in: order)
        sel.extend(to: "zz", in: order) // zz not in order
        #expect(sel.ids == ["a"]) // no change
    }
}
