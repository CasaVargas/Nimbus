import Testing
import SwiftUI
@testable import Nimbus

@Suite("FormSection")
@MainActor
struct FormSectionTests {
    @Test func rendersTitleAndRows() throws {
        let view = FormSection(title: "Configuration", footer: nil) {
            FormRow(label: "Name", help: nil) {
                Text("my-remote")
            }
            FormRow(label: "Type", help: "Provider type") {
                Text("s3")
            }
        }
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 200),
            named: "FormSection-basic"
        )
    }

    @Test func rendersWithFooter() throws {
        let view = FormSection(
            title: "Advanced",
            footer: "These fields are optional for most users."
        ) {
            FormRow(label: "Region", help: nil) {
                Text("us-east-1")
            }
        }
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 180),
            named: "FormSection-with-footer"
        )
    }
}
