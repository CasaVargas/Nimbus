import Testing
import SwiftUI
import AppKit
@testable import Nimbus

@Suite("Accessibility audit")
@MainActor
struct AccessibilityAuditTests {
    @Test func statusBadgeAllStatesHaveNonEmptyLabel() {
        let states: [CloudStatus] = [
            .local,
            .cloud,
            .downloading(progress: 0.0),
            .downloading(progress: 0.5),
            .downloading(progress: 1.0),
            .evicted,
            .error(reason: "Could not authenticate"),
        ]
        for s in states {
            let badge = StatusBadge(state: s)
            #expect(!badge.accessibilityLabelString.isEmpty,
                    "StatusBadge accessibility label was empty for state \(s)")
        }
    }

    @Test func statusBadgeProgressLabelIncludesPercentage() {
        let badge = StatusBadge(state: .downloading(progress: 0.47))
        #expect(badge.accessibilityLabelString == "Downloading 47 percent")
    }

    @Test func statusBadgeErrorLabelIncludesReason() {
        let badge = StatusBadge(state: .error(reason: "Server returned 401"))
        #expect(badge.accessibilityLabelString.contains("401"))
    }

    @Test func emptyStateRendersWithoutCrashing() {
        // Smoke test: SwiftUI's accessibility tree isn't easy to introspect from
        // a unit test, but materializing the view exercises NSHostingView and
        // catches crashes/preconditions.
        let view = EmptyState(icon: "folder", title: "Empty Folder", message: "test", action: nil)
        _ = NSHostingView(rootView: view)
    }

    @Test func emptyStateWithCTARendersWithoutCrashing() {
        let view = EmptyState(
            icon: "key.slash",
            title: "Sign In Required",
            message: "Reconnect to continue",
            action: .init(label: "Reconnect", perform: {})
        )
        _ = NSHostingView(rootView: view)
    }
}
