import Foundation
import Testing
@testable import Nimbus

@Suite("Mount defaults")
@MainActor
struct MountDefaultsTests {
    private func isolatedDefaults() -> UserDefaults {
        let name = "NimbusTests.MountDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func newDraftUsesGlobalDefaults() {
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.newMountAccess = .readOnly
        settings.newMountAutoMount = true

        let draft = MountDraft.make(settings: settings, editing: nil)

        #expect(draft.vfsMode == .readOnly)
        #expect(draft.autoMount)
    }

    @Test func editDraftPreservesConfiguration() {
        let existing = MountConfig(
            remote: "work:",
            mountPoint: "/Volumes/work",
            vfsMode: .readWrite,
            autoMount: false,
            backend: .nfs
        )
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.newMountAccess = .readOnly
        settings.newMountAutoMount = true

        let draft = MountDraft.make(settings: settings, editing: existing)

        #expect(draft.vfsMode == .readWrite)
        #expect(draft.autoMount == false)
    }
}
