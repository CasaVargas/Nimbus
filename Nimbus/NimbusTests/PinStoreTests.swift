import Testing
import Foundation
import FileProvider
@testable import Nimbus

@Suite("PinStore")
struct PinStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinStoreTests-\(UUID().uuidString)", isDirectory: true)

    @Test func pinAndUnpin() throws {
        let store = PinStore(directory: directory)
        #expect(store.pins(domain: "gdrive").isEmpty)
        try store.setPinned(true, identifiers: ["gdrive:Photos", "gdrive:a.txt"], domain: "gdrive")
        #expect(store.isPinned("gdrive:Photos", domain: "gdrive"))
        try store.setPinned(false, identifiers: ["gdrive:a.txt"], domain: "gdrive")
        #expect(store.pins(domain: "gdrive") == ["gdrive:Photos"])
        #expect(store.pins(domain: "other").isEmpty)
    }

    @Test func pinsSurviveAFreshStoreInstance() throws {
        try PinStore(directory: directory).setPinned(true, identifiers: ["s3:bucket/x"], domain: "s3")
        #expect(PinStore(directory: directory).isPinned("s3:bucket/x", domain: "s3"))
    }

    @Test func renameMovesTheItemAndItsDescendantsOnly() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["d:Photos", "d:Photos/2026/a.jpg", "d:Photos2", "d:Other"], domain: "d")
        try store.moved(from: "d:Photos", to: "d:Pictures", domain: "d")
        #expect(store.pins(domain: "d") == ["d:Pictures", "d:Pictures/2026/a.jpg", "d:Photos2", "d:Other"])
    }

    @Test func deleteDropsTheItemAndItsDescendants() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["d:A", "d:A/b", "d:AB"], domain: "d")
        try store.removed("d:A", domain: "d")
        #expect(store.pins(domain: "d") == ["d:AB"])
    }

    @Test func removeAllForgetsTheCloud() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["d:A"], domain: "d")
        store.removeAll(domain: "d")
        #expect(store.pins(domain: "d").isEmpty)
    }

    @Test func cloudNamesWithSpacesAndSlashesAreSafe() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["Personal Drive:x"], domain: "Personal Drive")
        try store.setPinned(true, identifiers: ["a/b:y"], domain: "a/b")
        #expect(store.isPinned("Personal Drive:x", domain: "Personal Drive"))
        #expect(store.isPinned("a/b:y", domain: "a/b"))
    }

    @Test func policyMapping() {
        #expect(PinPolicy.policy(isRoot: true, isPinned: false) == .downloadLazily)
        #expect(PinPolicy.policy(isRoot: true, isPinned: true) == .keepDownloaded)
        #expect(PinPolicy.policy(isRoot: false, isPinned: true) == .keepDownloaded)
        #expect(PinPolicy.policy(isRoot: false, isPinned: false) == .inherited)
    }

    @Test func parentIdentifiers() {
        #expect(PinPolicy.parentIdentifier(of: "d:Photos/2026/a.jpg") == "d:Photos/2026")
        #expect(PinPolicy.parentIdentifier(of: "d:a.jpg") == nil)
        #expect(PinPolicy.parentIdentifier(of: "My Drive:Docs/x") == "My Drive:Docs")
    }

    @Test func keptByAncestor() {
        let root = "ROOT"
        let pins: Set<String> = ["d:Photos"]
        #expect(PinPolicy.keptByAncestor("d:Photos/2026/a.jpg", pins: pins, rootKey: root))
        #expect(!PinPolicy.keptByAncestor("d:Photos", pins: pins, rootKey: root))
        #expect(!PinPolicy.keptByAncestor("d:Photos2/a.jpg", pins: pins, rootKey: root))
        #expect(PinPolicy.keptByAncestor("d:anything", pins: [root], rootKey: root))
        #expect(!PinPolicy.keptByAncestor(root, pins: [root], rootKey: root))
    }

    @Test func rootKeyMatchesFileProvider() {
        #expect(PinPolicy.rootKey == NSFileProviderItemIdentifier.rootContainer.rawValue)
    }

    @Test func changeLogRecordsPinsUnpinsAndMoves() throws {
        let store = PinStore(directory: directory)
        #expect(store.latestSequence(domain: "d") == 0)
        try store.setPinned(true, identifiers: ["d:A", "d:B"], domain: "d")
        let first = try #require(store.changes(domain: "d", after: 0))
        #expect(Set(first.identifiers) == ["d:A", "d:B"])
        #expect(first.latest == 2)
        try store.setPinned(false, identifiers: ["d:A"], domain: "d")
        try store.moved(from: "d:B", to: "d:C", domain: "d")
        let next = try #require(store.changes(domain: "d", after: first.latest))
        #expect(Set(next.identifiers) == ["d:A", "d:B", "d:C"])
        #expect(store.changes(domain: "d", after: next.latest)?.identifiers.isEmpty == true)
    }

    @Test func noOpWritesDontGrowTheLog() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["d:A"], domain: "d")
        try store.setPinned(true, identifiers: ["d:A"], domain: "d")
        #expect(store.latestSequence(domain: "d") == 1)
    }

    @Test func expiredAnchorsAreReported() throws {
        let store = PinStore(directory: directory)
        for i in 0..<(PinStore.changeLogLimit + 10) {
            try store.setPinned(true, identifiers: ["d:\(i)"], domain: "d")
        }
        #expect(store.changes(domain: "d", after: 0) == nil)
        #expect(store.changes(domain: "d", after: 9_999) == nil)
        #expect(store.changes(domain: "d", after: store.latestSequence(domain: "d")) != nil)
    }

    @Test func markChangedLogsEvenWithoutAPinChange() throws {
        let store = PinStore(directory: directory)
        try store.setPinned(true, identifiers: ["d:A"], domain: "d")
        try store.markChanged(["d:A"], domain: "d")
        #expect(store.latestSequence(domain: "d") == 2)
        #expect(store.changes(domain: "d", after: 1)?.identifiers == ["d:A"])
    }
}
