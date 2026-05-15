import Testing
import AppKit
@testable import Nimbus

@Suite("SelectionIntent")
@MainActor
struct SelectionIntentTests {
    @Test func plainClickIsSelect() {
        #expect(SelectionIntent.forClick(modifiers: []) == .select)
    }

    @Test func commandClickIsToggle() {
        #expect(SelectionIntent.forClick(modifiers: .command) == .toggle)
    }

    @Test func shiftClickIsExtend() {
        #expect(SelectionIntent.forClick(modifiers: .shift) == .extend)
    }

    @Test func commandTakesPrecedenceOverShift() {
        #expect(SelectionIntent.forClick(modifiers: [.command, .shift]) == .toggle)
    }

    @Test func selectThenShiftClickExtendsFromAnchor() {
        let sel = Selection<String>()
        let order = ["a", "b", "c", "d"]
        SelectionIntent.select.apply(to: sel, id: "b", ordering: order)
        SelectionIntent.extend.apply(to: sel, id: "d", ordering: order)
        #expect(sel.ids == ["b", "c", "d"])
        #expect(sel.anchor == "b")
    }

    @Test func commandClickTogglesAndPreservesAnchor() {
        let sel = Selection<String>()
        let order = ["a", "b", "c"]
        SelectionIntent.select.apply(to: sel, id: "a", ordering: order)
        SelectionIntent.toggle.apply(to: sel, id: "c", ordering: order)
        #expect(sel.ids == ["a", "c"])
        #expect(sel.anchor == "c")
    }

    @Test func extendAfterCommandClickRangesFromToggledAnchor() {
        let sel = Selection<String>()
        let order = ["a", "b", "c", "d"]
        SelectionIntent.select.apply(to: sel, id: "a", ordering: order)
        SelectionIntent.toggle.apply(to: sel, id: "c", ordering: order)
        SelectionIntent.extend.apply(to: sel, id: "d", ordering: order)
        #expect(sel.ids == ["a", "c", "d"])
    }
}
