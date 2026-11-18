import Foundation
import Testing
@testable import Nimbus

@Suite("AppGroup")
struct AppGroupTests {
    /// A `group.` identifier is dropped by macOS in a Developer ID build
    /// (no provisioning profile), which locks the extension out.
    @Test(arguments: [AppGroup.identifier, AppGroup.defaultIdentifier])
    func identifierIsTeamPrefixed(groupID: String) throws {
        #expect(!groupID.hasPrefix("group."))
        #expect(groupID.wholeMatch(of: /[A-Z0-9]{10}\.[A-Za-z0-9.-]+/) != nil)
    }

    @Test func identifierIsExpandedInHostBundle() throws {
        #expect(!AppGroup.identifier.contains("$("))
        #expect(!AppGroup.identifier.isEmpty)
    }

    /// In the test host (the app), the key must expand to the app's own ID.
    @Test func mainBundleIDMatchesHostBundle() throws {
        #expect(AppGroup.mainBundleID == Bundle.main.bundleIdentifier)
    }

    @Test func baseXcconfigMatchesDefaultIdentifier() throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: projectRoot.appendingPathComponent("Config/Base.xcconfig"), encoding: .utf8)
        let teamPrefix = "53MUTM55LC"
        let bundleID = "app.casavargas.nimbus"
        #expect(text.contains("NIMBUS_TEAM_PREFIX = \(teamPrefix)"))
        #expect(text.contains("NIMBUS_BUNDLE_ID = \(bundleID)"))
        #expect("\(teamPrefix).\(bundleID)" == AppGroup.defaultIdentifier)
        #expect(bundleID == AppGroup.defaultMainBundleID)
    }

    /// The entitlements, extension Info.plist and project definition must
    /// reference the build setting rather than hardcoding a group identifier.
    @Test(arguments: [
        "Nimbus/Nimbus.entitlements",
        "FileProviderExtension/FileProviderExtension.entitlements",
        "ShareExtension/ShareExtension.entitlements",
        "FileProviderExtension/Info.plist",
        "project.yml",
    ])
    func everyDeclarationNamesTheSameGroup(path: String) throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        #expect(text.contains("$(NIMBUS_APP_GROUP)"))
        #expect(!text.contains("53MUTM55LC.app.casavargas.nimbus"))
        #expect(!text.contains("group.app.casavargas.nimbus"))
    }
}
