import Testing
import SwiftUI
@testable import Nimbus

@Suite("SheetChrome")
@MainActor
struct SheetChromeTests {
    @Test func rendersTitleOnly() throws {
        let view = SheetChrome(
            title: "Add Remote",
            subtitle: nil,
            body: { Text("body content") },
            actions: { EmptyView() }
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 500, height: 240),
            named: "SheetChrome-title-only"
        )
    }

    @Test func rendersTitleSubtitleAndActions() throws {
        let view = SheetChrome(
            title: "Edit Remote",
            subtitle: "gdrive",
            body: { Text("body content") },
            actions: {
                HStack {
                    Button("Cancel") {}
                    Button("Save") {}.buttonStyle(.borderedProminent)
                }
            }
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 500, height: 280),
            named: "SheetChrome-full"
        )
    }
}
