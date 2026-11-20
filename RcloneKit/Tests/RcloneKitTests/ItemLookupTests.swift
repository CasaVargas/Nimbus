import Foundation
import Testing
@testable import RcloneKit

/// `item(fs:remote:)`: one entry by path through `operations/stat`.
@Suite("Item lookup", .serialized)
struct ItemLookupTests {
    @Test func returnsTheEntry() async throws {
        MockURLProtocol.reset(endpoint: "operations/stat")
        MockURLProtocol.enqueue(endpoint: "operations/stat", json: #"""
        {"item": {"Path": "Photos/2022/IMG_1.HEIC", "Name": "IMG_1.HEIC", "Size": 1778129,
                  "MimeType": "image/heic", "ModTime": "2022-07-30T17:32:06Z", "IsDir": false}}
        """#)
        let item = try #require(try await makeTestClient().item(fs: "cloud:", remote: "Photos/2022/IMG_1.HEIC"))
        #expect(item.path == "Photos/2022/IMG_1.HEIC")
        #expect(item.name == "IMG_1.HEIC")
        #expect(item.size == 1_778_129)
        #expect(item.isDir == false)
        #expect(item.modTime == Date(timeIntervalSince1970: 1_659_202_326))

        let body = try #require(MockURLProtocol.lastRequestBodies["operations/stat"])
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["fs"] as? String == "cloud:")
        #expect(json["remote"] as? String == "Photos/2022/IMG_1.HEIC")
    }

    @Test func returnsNilForAMissingPath() async throws {
        MockURLProtocol.reset(endpoint: "operations/stat")
        MockURLProtocol.enqueue(endpoint: "operations/stat", json: #"{"item": null}"#)
        #expect(try await makeTestClient().item(fs: "cloud:", remote: "no/such/file") == nil)
    }
}
