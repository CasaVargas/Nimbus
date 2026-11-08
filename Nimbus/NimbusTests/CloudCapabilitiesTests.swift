import Testing
import Foundation
@testable import Nimbus

@Suite("CloudCapabilities")
struct CloudCapabilitiesTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("caps-\(UUID().uuidString)/capabilities.json")

    @Test func unknownCloudsCannotShare() {
        #expect(!CloudCapabilities(url: url).canShare(cloud: "gdrive"))
    }

    @Test func replaceRecordsAndDropsClouds() throws {
        let store = CloudCapabilities(url: url)
        try store.replace(with: ["gdrive": .init(shareLinks: true), "nas": .init(shareLinks: false)])
        #expect(store.canShare(cloud: "gdrive"))
        #expect(!store.canShare(cloud: "nas"))
        try store.replace(with: ["nas": .init(shareLinks: false)])
        #expect(!CloudCapabilities(url: url).canShare(cloud: "gdrive"))
    }
}
