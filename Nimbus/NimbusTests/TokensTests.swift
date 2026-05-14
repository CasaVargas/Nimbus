import Testing
import SwiftUI
@testable import Nimbus

@Suite("Design system tokens")
struct TokensTests {
    @Test func spacingScaleIs4ptBased() {
        #expect(DesignSystem.Spacing.xs == 4)
        #expect(DesignSystem.Spacing.s  == 8)
        #expect(DesignSystem.Spacing.m  == 12)
        #expect(DesignSystem.Spacing.l  == 16)
        #expect(DesignSystem.Spacing.xl == 24)
        #expect(DesignSystem.Spacing.xxl == 32)
    }

    @Test func radiusScaleMatchesSpec() {
        #expect(DesignSystem.Radius.xs == 2)
        #expect(DesignSystem.Radius.s  == 4)
        #expect(DesignSystem.Radius.pill == 6)
        #expect(DesignSystem.Radius.card == 10)
        #expect(DesignSystem.Radius.sheet == 14)
    }

    @Test func motionDurationsAreUnder250ms() {
        #expect(DesignSystem.Motion.snappyDuration  == 0.18)
        #expect(DesignSystem.Motion.smoothDuration  == 0.22)
        #expect(DesignSystem.Motion.springyDuration == 0.25)
    }

    @MainActor
    @Test func semanticColorsAreNonNilInDefaultAppearance() {
        // Resolves through NSColor — must produce a non-default-clear color in current appearance.
        let resolved = NSColor(DesignSystem.Color.semantic.accent).cgColor
        #expect(resolved.alpha > 0)
    }
}
