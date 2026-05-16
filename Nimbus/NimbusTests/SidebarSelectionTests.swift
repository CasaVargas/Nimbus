import Testing
@testable import Nimbus

@Suite("SidebarSelection.nextSelection")
struct SidebarSelectionTests {
    @Test func keepsValidRemoteSelection() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "b", "c"])
        #expect(result == .remote("b"))
    }

    @Test func deletedSelectedRemoteFallsBackToFirst() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "c"])
        #expect(result == .remote("a"))
    }

    @Test func deletingLastRemoteClearsSelection() {
        let result = nextSelection(current: .remote("only"), remotes: [])
        #expect(result == nil)
    }

    @Test func nilSelectionAutoSelectsFirstRemote() {
        let result = nextSelection(current: nil, remotes: ["a", "b"])
        #expect(result == .remote("a"))
    }

    @Test func nilSelectionStaysNilWhenNoRemotes() {
        let result = nextSelection(current: nil, remotes: [])
        #expect(result == nil)
    }

    @Test func nonRemoteSelectionPassesThroughUnchanged() {
        for remotes in [[], ["a", "b"]] as [[String]] {
            #expect(nextSelection(current: .mounts, remotes: remotes) == .mounts)
            #expect(nextSelection(current: .transfers, remotes: remotes) == .transfers)
            #expect(nextSelection(current: .copySync, remotes: remotes) == .copySync)
        }
    }
}
