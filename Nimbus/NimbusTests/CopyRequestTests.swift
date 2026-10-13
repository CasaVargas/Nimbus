import Testing
@testable import Nimbus

@Suite("CopyRequest")
@MainActor
struct CopyRequestTests {
    @Test func requestKeepsProvidedDefaultAndAllowsOverride() {
        let target = DropIntent.DropTarget(remote: "target", path: "/Inbox")
        let items = [DropIntent.Item(name: "report.pdf", path: "/report.pdf", size: 42, isDir: false)]

        var request = CopyRequest(
            sourceRemote: "source",
            target: target,
            items: items,
            conflictPolicy: .skip
        )

        #expect(request.conflictPolicy == .skip)

        request.conflictPolicy = .overwrite

        #expect(request.conflictPolicy == .overwrite)
    }
}
