import Foundation
import Testing
@testable import RcloneKit

// Owns the operations/publiclink and operations/fsinfo mock endpoints.
@Suite("Share links", .serialized)
struct ShareLinkTests {
    @Test func publicLinkSendsPathAndExpiry() async throws {
        MockURLProtocol.reset(endpoint: "operations/publiclink")
        MockURLProtocol.enqueue(endpoint: "operations/publiclink",
                                json: #"{"url": "https://example.com/s/abc"}"#)
        let url = try await makeTestClient().publicLink(fs: "gdrive:", remote: "Docs/a.pdf", expire: "7d")
        #expect(url == URL(string: "https://example.com/s/abc"))
        let body = try #require(MockURLProtocol.lastRequestBodies["operations/publiclink"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["fs"] as? String == "gdrive:")
        #expect(json["remote"] as? String == "Docs/a.pdf")
        #expect(json["expire"] as? String == "7d")
        #expect(json["unlink"] == nil)
    }

    @Test func unlinkReturnsNoURL() async throws {
        MockURLProtocol.reset(endpoint: "operations/publiclink")
        MockURLProtocol.enqueue(endpoint: "operations/publiclink", json: #"{"url": ""}"#)
        let url = try await makeTestClient().publicLink(fs: "d:", remote: "x", unlink: true)
        #expect(url == nil)
        let body = try #require(MockURLProtocol.lastRequestBodies["operations/publiclink"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["unlink"] as? Bool == true)
    }

    @Test func featuresReadsPublicLinkAndToleratesNonBooleans() async throws {
        MockURLProtocol.reset(endpoint: "operations/fsinfo")
        MockURLProtocol.enqueue(endpoint: "operations/fsinfo", json: #"""
        {"Name": "s3x", "Features": {"PublicLink": true, "Copy": true, "Odd": "x"}}
        """#)
        let features = try await makeTestClient().features(fs: "s3x:")
        #expect(features.publicLink)
        MockURLProtocol.enqueue(endpoint: "operations/fsinfo", json: #"{"Name": "loc", "Features": {"PublicLink": false}}"#)
        #expect(try await makeTestClient().features(fs: "loc:").publicLink == false)
    }

    @Test func hashTypesDecodeInOrder() async throws {
        MockURLProtocol.reset(endpoint: "operations/fsinfo")
        MockURLProtocol.enqueue(endpoint: "operations/fsinfo", json: #"""
        {"Name": "s3x", "Features": {"PublicLink": true}, "Hashes": ["md5", "sha1"]}
        """#)
        #expect(try await makeTestClient().hashTypes(fs: "s3x:") == ["md5", "sha1"])
    }

    @Test func hashTypesEmptyForCryptOrMissing() async throws {
        MockURLProtocol.reset(endpoint: "operations/fsinfo")
        MockURLProtocol.enqueue(endpoint: "operations/fsinfo", json: #"{"Name": "c", "Features": {}, "Hashes": []}"#)
        MockURLProtocol.enqueue(endpoint: "operations/fsinfo", json: #"{"Name": "n", "Features": {}, "Hashes": null}"#)
        #expect(try await makeTestClient().hashTypes(fs: "c:") == [])
        #expect(try await makeTestClient().hashTypes(fs: "n:") == [])
    }
}
