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
        sel.toggle("c", in: order)
        #expect(sel.ids == ["a", "c"])
        sel.toggle("a", in: order)
        #expect(sel.ids == ["c"])
    }

    @Test func extendFromAnchorSelectsRangeInclusive() {
        let sel = Selection<String>()
        sel.select("b", in: order)
        sel.extend(to: "d", in: order)
        #expect(sel.ids == ["b", "c", "d"])
        #expect(sel.anchor == "b") // anchor doesn't move on extend
    }

    @Test func consecutiveExtendStreakKeepsBaseFrozenAndShrinksRange() {
        let sel = Selection<String>()
        // Plain select commits anchor=b, base={b}.
        sel.select("b", in: order)
        // First extend in the streak: base ∪ b…d.
        sel.extend(to: "d", in: order)
        #expect(sel.ids == ["b", "c", "d"])
        // Second extend WITHOUT a new anchor commit: base stays {b},
        // range recomputes b…c — must SHRINK, not accumulate the prior d.
        sel.extend(to: "c", in: order)
        #expect(sel.ids == ["b", "c"])
        #expect(sel.anchor == "b")
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
        sel.toggle("b", in: order)
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
        #expect(sel.anchor == "a") // anchor survives the no-op
    }

    @Test func replaceWithEmptySetClearsAnchor() {
        let sel = Selection<String>()
        sel.select("a", in: order)
        sel.replace(with: [], in: order)
        #expect(sel.ids.isEmpty)
        #expect(sel.anchor == nil)
    }

    @Test func extendSurvivesReorder() {
        let sel = Selection<String>()
        sel.select("b", in: order)
        let reordered = ["e", "d", "c", "b", "a"]
        sel.extend(to: "d", in: reordered)
        #expect(sel.ids == ["d", "c", "b"]) // range in the new ordering
        #expect(sel.anchor == "b")
    }

    @Test func extendToAnchorPreservesDisjointSelection() {
        let sel = Selection<String>()
        sel.select("c", in: order)
        sel.toggle("d", in: order)
        sel.toggle("e", in: order)
        // After toggles, anchor is "e" (toggle moves anchor on insert).
        // Finder-accurate: ⇧-click on the anchor after disjoint ⌘-clicks
        // preserves the disjoint selection (base ∪ range e…e) — it does
        // NOT collapse to the single anchor item.
        sel.extend(to: "e", in: order)
        #expect(sel.ids == ["c", "d", "e"])
    }
}
