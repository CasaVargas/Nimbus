import Testing
import SwiftUI
@testable import Nimbus

@Suite("OnboardingCard")
@MainActor
struct OnboardingCardTests {
    @Test func rendersPendingState() throws {
        let view = OnboardingCard(
            state: .pending,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connect a cloud provider to get started.",
            primaryAction: nil,
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-pending"
        )
    }

    @Test func rendersInProgressState() throws {
        let view = OnboardingCard(
            state: .inProgress,
            icon: "bolt",
            title: "Rclone Daemon",
            message: "Connecting to rclone…",
            primaryAction: nil,
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-inProgress"
        )
    }

    @Test func rendersCompleteState() throws {
        let view = OnboardingCard(
            state: .complete,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connected to gdrive.",
            primaryAction: nil,
            secondaryAction: .init(label: "Mount it for Finder →", perform: {})
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 120), named: "OnboardingCard-complete"
        )
    }

    @Test func rendersActionRequiredState() throws {
        let view = OnboardingCard(
            state: .actionRequired,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connect a cloud provider to get started.",
            primaryAction: .init(label: "Add Remote", perform: {}),
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-actionRequired"
        )
    }

    @Test func rendersCompleteWithPrimaryAction() throws {
        let view = OnboardingCard(
            state: .complete,
            icon: "checkmark.seal.fill",
            title: "You're All Set",
            message: "Nimbus is ready to manage your cloud storage.",
            primaryAction: .init(label: "Done", perform: {}),
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-completeWithPrimary"
        )
    }
}
