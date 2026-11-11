import Foundation
import Testing
@testable import Nimbus

@Suite("ItemBadges")
struct ItemBadgesTests {
    @Test(arguments: [
        (false, false, [String]()),
        (true, false, [ItemBadges.pinned]),
        (false, true, [ItemBadges.uploadFailed]),
        // Finder shows only the first badge: the failure wins.
        (true, true, [ItemBadges.uploadFailed, ItemBadges.pinned]),
    ])
    func identifiers(pinned: Bool, uploadFailed: Bool, expected: [String]) {
        #expect(ItemBadges.identifiers(pinned: pinned, uploadFailed: uploadFailed) == expected)
    }

    @Test func healthyItemsKeepTheirPreBadgeMetadataVersion() {
        for keepState in 0...2 {
            #expect(ItemBadges.metadataSuffix(keepState: keepState, uploadFailed: false) == [UInt8(keepState)])
        }
    }

    @Test func aFailedUploadChangesTheMetadataVersion() {
        #expect(ItemBadges.metadataSuffix(keepState: 1, uploadFailed: true) == [1, 1])
        #expect(ItemBadges.metadataSuffix(keepState: 0, uploadFailed: true)
                != ItemBadges.metadataSuffix(keepState: 0, uploadFailed: false))
    }

    @Test func cancellationsAreNotFailures() {
        #expect(!UploadFailurePolicy.shouldRecord(CancellationError()))
        #expect(!UploadFailurePolicy.shouldRecord(CocoaError(.userCancelled)))
        #expect(!UploadFailurePolicy.shouldRecord(URLError(.cancelled)))
        #expect(UploadFailurePolicy.shouldRecord(URLError(.notConnectedToInternet)))
        #expect(UploadFailurePolicy.shouldRecord(CocoaError(.fileWriteUnknown)))
    }

    /// Every badge the code can return must be declared in the extension's
    /// Info.plist (and in project.yml, which generates it) with a system
    /// badge image, or Finder silently shows nothing.
    @Test func everyBadgeIsDeclaredInTheGeneratedInfoPlist() throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("FileProviderExtension/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ext = try #require(plist["NSExtension"] as? [String: Any])
        let decorations = try #require(ext["NSFileProviderDecorations"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: decorations.compactMap { entry in
            (entry["Identifier"] as? String).map { ($0, entry) }
        })
        for id in ItemBadges.all {
            let entry = try #require(byID[id], "\(id) missing from Info.plist")
            #expect(entry["Category"] as? String == "Badge")
            #expect((entry["BadgeImageType"] as? String)?.hasPrefix("com.apple.icon-decoration.badge.") == true)
            #expect((entry["Label"] as? String)?.isEmpty == false)
        }
        #expect(Set(byID.keys) == Set(ItemBadges.all))

        let yml = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        for id in ItemBadges.all { #expect(yml.contains("Identifier: \(id)")) }
    }
}

@Suite("UploadFailureStore")
struct UploadFailureStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UploadFailureStoreTests-\(UUID().uuidString)", isDirectory: true)

    @Test func recordAndClearReportWhetherAnythingChanged() throws {
        let store = UploadFailureStore(directory: directory)
        #expect(try store.record("d:a.txt", domain: "d"))
        #expect(try !store.record("d:a.txt", domain: "d"))
        #expect(store.hasFailed("d:a.txt", domain: "d"))
        #expect(try store.clear(["d:a.txt", "d:other"], domain: "d"))
        #expect(try !store.clear(["d:a.txt"], domain: "d"))
        #expect(store.failures(domain: "d").isEmpty)
    }

    @Test func failuresSurviveAFreshStoreInstance() throws {
        try UploadFailureStore(directory: directory).record("s3:bucket/x", domain: "s3")
        #expect(UploadFailureStore(directory: directory).hasFailed("s3:bucket/x", domain: "s3"))
    }

    @Test func cloudsAreKeptApart() throws {
        let store = UploadFailureStore(directory: directory)
        try store.record("a:x", domain: "a")
        #expect(store.failures(domain: "b").isEmpty)
    }

    @Test func renameMovesTheItemAndItsDescendantsOnly() throws {
        let store = UploadFailureStore(directory: directory)
        for id in ["d:Photos/a.jpg", "d:Photos/2026/b.jpg", "d:Photos2/c.jpg", "d:Other"] {
            try store.record(id, domain: "d")
        }
        try store.moved(from: "d:Photos", to: "d:Pictures", domain: "d")
        #expect(store.failures(domain: "d") == ["d:Pictures/a.jpg", "d:Pictures/2026/b.jpg", "d:Photos2/c.jpg", "d:Other"])
    }

    @Test func deleteDropsTheItemAndItsDescendants() throws {
        let store = UploadFailureStore(directory: directory)
        for id in ["d:A", "d:A/b", "d:AB"] { try store.record(id, domain: "d") }
        try store.removed("d:A", domain: "d")
        #expect(store.failures(domain: "d") == ["d:AB"])
    }

    @Test func removeAllForgetsTheCloud() throws {
        let store = UploadFailureStore(directory: directory)
        try store.record("d:x", domain: "d")
        store.removeAll(domain: "d")
        #expect(store.failures(domain: "d").isEmpty)
        #expect(UploadFailureStore(directory: directory).failures(domain: "d").isEmpty)
    }
}
