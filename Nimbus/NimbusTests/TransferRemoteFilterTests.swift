import Foundation
import Testing
@testable import Nimbus

@Suite("Transfer remote filter")
struct TransferRemoteFilterTests {
    private func transfer(src: String, dst: String) -> Transfer {
        Transfer(jobID: nil, operation: .copy, srcFs: src, dstFs: dst,
                 startedAt: Date(), completedAt: nil, status: .active,
                 origin: .manual, nimbusUUID: UUID())
    }

    @Test func matchesSourceAndDestination() {
        let t = transfer(src: "Backups:x", dst: "Personal Drive:y")
        #expect(t.involves(remote: "Backups"))
        #expect(t.involves(remote: "Personal Drive"))
    }

    @Test func requiresWholeRemoteName() {
        let t = transfer(src: "Backups:x", dst: "Personal Drive2:z")
        #expect(!t.involves(remote: "Personal"))
        #expect(!t.involves(remote: "Personal Drive"))
    }
}
