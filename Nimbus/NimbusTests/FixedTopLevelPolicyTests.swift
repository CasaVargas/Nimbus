import Foundation
import Testing
@testable import Nimbus

@Suite("FixedTopLevelPolicy")
struct FixedTopLevelPolicyTests {
    @Test func topLevelPathDetection() {
        #expect(!FixedTopLevelPolicy.isTopLevelPath(""))
        #expect(FixedTopLevelPolicy.isTopLevelPath("gdrive"))
        #expect(!FixedTopLevelPolicy.isTopLevelPath("gdrive/docs"))
        #expect(!FixedTopLevelPolicy.isTopLevelPath("/gdrive"))
        #expect(!FixedTopLevelPolicy.isTopLevelPath("gdrive/"))
    }

    @Test func rootMetadataVersionDistinguishesFixedTopLevel() {
        #expect(FixedTopLevelPolicy.rootMetadataVersion(hasFixedTopLevel: false) == Data([0]))
        #expect(FixedTopLevelPolicy.rootMetadataVersion(hasFixedTopLevel: true) == Data([1]))
    }

    @Test func childMetadataSuffixOnlyMarksProtectedTopLevelFolders() {
        #expect(FixedTopLevelPolicy.childMetadataSuffix(isDir: true, isTopLevel: true, hasFixedTopLevel: true) == [2])
        #expect(FixedTopLevelPolicy.childMetadataSuffix(isDir: true, isTopLevel: true, hasFixedTopLevel: false) == [])
        #expect(FixedTopLevelPolicy.childMetadataSuffix(isDir: true, isTopLevel: false, hasFixedTopLevel: true) == [])
        #expect(FixedTopLevelPolicy.childMetadataSuffix(isDir: false, isTopLevel: true, hasFixedTopLevel: true) == [])
    }

    @Test func childMetadataSuffixDoesNotCollideWithBadgeSuffixes() {
        var seen = Set<[UInt8]>()
        for keepState in 0...2 {
            for uploadFailed in [false, true] {
                for fixed in [false, true] {
                    let bytes = ItemBadges.metadataSuffix(keepState: keepState, uploadFailed: uploadFailed)
                        + FixedTopLevelPolicy.childMetadataSuffix(isDir: true, isTopLevel: true, hasFixedTopLevel: fixed)
                    #expect(seen.insert(bytes).inserted)
                }
            }
        }
    }

    @Test func rootChangeTransitionDecision() {
        // First pass: ordinary remotes stay quiet; fixed-top-level remotes report once.
        #expect(!FixedTopLevelPolicy.shouldReportRootChange(current: false, lastReported: nil))
        #expect(FixedTopLevelPolicy.shouldReportRootChange(current: true, lastReported: nil))

        // Steady state: no repeat updates.
        #expect(!FixedTopLevelPolicy.shouldReportRootChange(current: false, lastReported: false))
        #expect(!FixedTopLevelPolicy.shouldReportRootChange(current: true, lastReported: true))

        // Transitions in either direction report once.
        #expect(FixedTopLevelPolicy.shouldReportRootChange(current: true, lastReported: false))
        #expect(FixedTopLevelPolicy.shouldReportRootChange(current: false, lastReported: true))
    }

    @Test func reportedStatePersistsAndClearsUnderFileProviderSync() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixed-top-level-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(FixedTopLevelPolicy.readReportedState(remoteName: "clouds", base: base) == nil)
        #expect(FixedTopLevelPolicy.writeReportedState(true, remoteName: "clouds", base: base))
        #expect(FixedTopLevelPolicy.readReportedState(remoteName: "clouds", base: base) == true)

        let expectedPath = base
            .appendingPathComponent("FileProviderSync/clouds/reported-fixed-top-level")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path))

        #expect(FixedTopLevelPolicy.writeReportedState(false, remoteName: "clouds", base: base))
        #expect(FixedTopLevelPolicy.readReportedState(remoteName: "clouds", base: base) == false)

        FixedTopLevelPolicy.clearReportedState(remoteName: "clouds", base: base)
        #expect(FixedTopLevelPolicy.readReportedState(remoteName: "clouds", base: base) == nil)
    }
}
