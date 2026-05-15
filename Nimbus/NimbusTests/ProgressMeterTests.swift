import Testing
import SwiftUI
@testable import Nimbus

@Suite("ProgressMeter")
@MainActor
struct ProgressMeterTests {
    @Test func rendersZeroProgress() throws {
        let view = ProgressMeter(progress: 0.0, speed: nil, eta: nil)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 180, height: 24), named: "ProgressMeter-0"
        )
    }

    @Test func rendersHalfProgress() throws {
        let view = ProgressMeter(progress: 0.5, speed: 1_500_000, eta: 12)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 240, height: 36), named: "ProgressMeter-50"
        )
    }

    @Test func rendersFullProgress() throws {
        let view = ProgressMeter(progress: 1.0, speed: nil, eta: nil)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 180, height: 24), named: "ProgressMeter-100"
        )
    }

    @Test func clampsProgressToValidRange() {
        let belowZero = ProgressMeter(progress: -0.5, speed: nil, eta: nil)
        #expect(belowZero.clampedProgress == 0.0)
        let aboveOne = ProgressMeter(progress: 1.5, speed: nil, eta: nil)
        #expect(aboveOne.clampedProgress == 1.0)
        let inRange = ProgressMeter(progress: 0.42, speed: nil, eta: nil)
        #expect(inRange.clampedProgress == 0.42)
    }
}
