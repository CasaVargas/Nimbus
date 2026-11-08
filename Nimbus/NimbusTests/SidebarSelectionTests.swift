import Testing
@testable import Nimbus

@Suite("SidebarSelection.nextSelection")
struct SidebarSelectionTests {
    @Test func keepsValidRemoteSelection() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "b", "c"])
        #expect(result == .remote("b"))
    }

    @Test func deletedSelectedRemoteFallsBackToHome() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "c"])
        #expect(result == .home)
    }

    @Test func deletingLastRemoteLandsOnHome() {
        let result = nextSelection(current: .remote("only"), remotes: [])
        #expect(result == .home)
    }

    @Test func nilSelectionOpensHome() {
        #expect(nextSelection(current: nil, remotes: ["a", "b"]) == .home)
        #expect(nextSelection(current: nil, remotes: []) == .home)
    }

    @Test func nonRemoteSelectionPassesThroughUnchanged() {
        for remotes in [[], ["a", "b"]] as [[String]] {
            #expect(nextSelection(current: .copySync, remotes: remotes) == .copySync)
            #expect(nextSelection(current: .home, remotes: remotes) == .home)
        }
    }
}
