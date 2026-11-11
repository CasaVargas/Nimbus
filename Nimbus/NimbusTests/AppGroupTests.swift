import Foundation
import Testing
@testable import Nimbus

@Suite("AppGroup")
struct AppGroupTests {
    /// A `group.` identifier is dropped by macOS in a Developer ID build
    /// (no provisioning profile), which locks the extension out.
    @Test func identifierIsTeamPrefixed() throws {
        #expect(!AppGroup.identifier.hasPrefix("group."))
        #expect(AppGroup.identifier.wholeMatch(of: /[A-Z0-9]{10}\.[a-z.]+/) != nil)
    }

    /// The code, both entitlements and the extension's document group must
    /// name the same group, or the app and the extension stop sharing.
    @Test(arguments: [
        "Nimbus/Nimbus.entitlements",
        "FileProviderExtension/FileProviderExtension.entitlements",
        "FileProviderExtension/Info.plist",
        "project.yml",
    ])
    func everyDeclarationNamesTheSameGroup(path: String) throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        #expect(text.contains(AppGroup.identifier))
        #expect(!text.contains("group.app.casavargas.nimbus"))
    }
}
