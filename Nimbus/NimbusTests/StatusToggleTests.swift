import Testing
import SwiftUI
@testable import Nimbus

@Suite("StatusToggle")
@MainActor
struct StatusToggleTests {
    @Test func accessibilityLabelMatchesState() {
        #expect(StatusToggleState.off.accessibilityLabel == "Off")
        #expect(StatusToggleState.on.accessibilityLabel == "On")
        #expect(StatusToggleState.mounting.accessibilityLabel == "Mounting")
        #expect(StatusToggleState.unmounting.accessibilityLabel == "Unmounting")
        #expect(StatusToggleState.error(reason: "Boom").accessibilityLabel == "Error: Boom")
    }

    @Test func equatableCompareSameState() {
        #expect(StatusToggleState.on == StatusToggleState.on)
        #expect(StatusToggleState.off == StatusToggleState.off)
        #expect(StatusToggleState.mounting == StatusToggleState.mounting)
        #expect(StatusToggleState.error(reason: "x") == StatusToggleState.error(reason: "x"))
        #expect(StatusToggleState.error(reason: "x") != StatusToggleState.error(reason: "y"))
    }

    @Test func transitioningStatesDisableInteraction() {
        #expect(StatusToggleState.mounting.isTransitioning)
        #expect(StatusToggleState.unmounting.isTransitioning)
        #expect(StatusToggleState.on.isTransitioning == false)
        #expect(StatusToggleState.off.isTransitioning == false)
        #expect(StatusToggleState.error(reason: "x").isTransitioning == false)
    }

    @Test func visualIsOnReflectsState() {
        #expect(StatusToggleState.on.visualIsOn)
        #expect(StatusToggleState.unmounting.visualIsOn)
        #expect(StatusToggleState.off.visualIsOn == false)
        #expect(StatusToggleState.mounting.visualIsOn == false)
        #expect(StatusToggleState.error(reason: "x").visualIsOn == false)
    }
}
