import Foundation
import Testing
@testable import Nimbus

struct TransferEndpointTests {
    @Test func fsForCloudRoot() {
        #expect(TransferEndpoint.cloud(remote: "b2", path: "").fs == "b2:")
    }

    @Test func fsForCloudPath() {
        #expect(TransferEndpoint.cloud(remote: "b2", path: "mac/Docs").fs == "b2:mac/Docs")
    }

    @Test func fsForLocal() {
        #expect(TransferEndpoint.local(path: "/Users/j/Documents").fs == "/Users/j/Documents")
    }

    @Test func appendingTrimsSlashes() {
        let base = TransferEndpoint.cloud(remote: "b2", path: "mac/")
        #expect(base.appending("/.nimbus-versions").fs == "b2:mac/.nimbus-versions")
        #expect(TransferEndpoint.cloud(remote: "b2", path: "").appending("x").fs == "b2:x")
        #expect(TransferEndpoint.local(path: "/Users/j/").appending("old/").fs == "/Users/j/old")
    }

    @Test func containsChild() {
        let parent = TransferEndpoint.cloud(remote: "b2", path: "mac")
        #expect(parent.contains(.cloud(remote: "b2", path: "mac/Docs")))
        #expect(parent.contains(parent))
        #expect(TransferEndpoint.cloud(remote: "b2", path: "").contains(.cloud(remote: "b2", path: "anything")))
    }

    @Test func doesNotContainSiblingPrefix() {
        #expect(!TransferEndpoint.cloud(remote: "b2", path: "mac").contains(.cloud(remote: "b2", path: "mac2")))
        #expect(!TransferEndpoint.cloud(remote: "b2", path: "mac/Docs").contains(.cloud(remote: "b2", path: "mac")))
    }

    @Test func differentCloudsNeverContain() {
        #expect(!TransferEndpoint.cloud(remote: "b2", path: "").contains(.cloud(remote: "b22", path: "")))
        #expect(!TransferEndpoint.cloud(remote: "b2", path: "").contains(.local(path: "/b2")))
    }

    @Test func localContainsLocalChild() {
        let docs = TransferEndpoint.local(path: "/Users/j/Documents")
        #expect(docs.contains(.local(path: "/Users/j/Documents/Taxes")))
        #expect(!docs.contains(.local(path: "/Users/j/Documents2")))
        #expect(TransferEndpoint.local(path: "/").contains(.local(path: "/Volumes/X")))
    }

    @Test func displayNames() {
        #expect(TransferEndpoint.cloud(remote: "b2", path: "").displayName == "b2")
        #expect(TransferEndpoint.cloud(remote: "b2", path: "mac/Docs").displayName == "Docs")
        #expect(TransferEndpoint.local(path: "/Users/j/Documents").displayName == "Documents")
        #expect(TransferEndpoint.cloud(remote: "b2", path: "x").cloudName == "b2")
        #expect(TransferEndpoint.local(path: "/x").cloudName == nil)
    }

    @Test(arguments: [
        TransferEndpoint.local(path: "/Users/j/Résumé \"final\""),
        TransferEndpoint.cloud(remote: "b2", path: "mac/Docs"),
    ])
    func codableRoundTrip(endpoint: TransferEndpoint) throws {
        let data = try JSONEncoder().encode(endpoint)
        #expect(try JSONDecoder().decode(TransferEndpoint.self, from: data) == endpoint)
    }

    @Test func codableShapeIsReadable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let local = String(decoding: try encoder.encode(TransferEndpoint.local(path: "/a")), as: UTF8.self)
        #expect(local == #"{"kind":"local","path":"\/a"}"#)
        let cloud = String(decoding: try encoder.encode(TransferEndpoint.cloud(remote: "b2", path: "x")), as: UTF8.self)
        #expect(cloud == #"{"kind":"cloud","path":"x","remote":"b2"}"#)
    }
}
