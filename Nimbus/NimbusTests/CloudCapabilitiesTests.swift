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

    @Test func unknownCloudsDoNotHaveFixedTopLevel() {
        #expect(!CloudCapabilities(url: url).hasFixedTopLevel(cloud: "clouds"))
    }

    @Test func replaceRecordsAndDropsClouds() throws {
        let store = CloudCapabilities(url: url)
        try store.replace(with: ["gdrive": .init(shareLinks: true), "nas": .init(shareLinks: false)])
        #expect(store.canShare(cloud: "gdrive"))
        #expect(!store.canShare(cloud: "nas"))
        try store.replace(with: ["nas": .init(shareLinks: false)])
        #expect(!CloudCapabilities(url: url).canShare(cloud: "gdrive"))
    }

    @Test func fixedTopLevelRoundTrips() throws {
        let store = CloudCapabilities(url: url)
        try store.replace(with: [
            "clouds": .init(shareLinks: false, fixedTopLevel: true),
            "gdrive": .init(shareLinks: true),
        ])
        let reloaded = CloudCapabilities(url: url)
        #expect(reloaded.hasFixedTopLevel(cloud: "clouds"))
        #expect(!reloaded.hasFixedTopLevel(cloud: "gdrive"))
        #expect(reloaded.canShare(cloud: "gdrive"))
    }

    /// The extension keeps one store for its whole life, so it must see the
    /// app's later rewrites without a run-loop turn in between.
    @Test func aLongLivedStoreSeesALaterRewrite() throws {
        try CloudCapabilities(url: url).replace(with: ["clouds": .init(shareLinks: false)])
        let reader = CloudCapabilities(url: url)
        #expect(!reader.hasFixedTopLevel(cloud: "clouds"))
        try CloudCapabilities(url: url).replace(with: ["clouds": .init(shareLinks: false, fixedTopLevel: true)])
        #expect(reader.hasFixedTopLevel(cloud: "clouds"))
    }

    @Test func oldJSONWithoutFixedTopLevelDecodesAsFalse() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"gdrive":{"shareLinks":true}}"#.utf8).write(to: url, options: .atomic)
        let store = CloudCapabilities(url: url)
        #expect(store.canShare(cloud: "gdrive"))
        #expect(!store.hasFixedTopLevel(cloud: "gdrive"))
    }
}
