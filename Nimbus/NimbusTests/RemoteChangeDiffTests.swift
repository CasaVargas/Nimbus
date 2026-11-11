import Testing
import Foundation
@testable import Nimbus

@Suite("RemoteChangeDiff")
struct RemoteChangeDiffTests {
    private func file(_ id: String, size: Int64 = 1, mod: TimeInterval? = 100, keep: Int? = 0) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: String(id.split(separator: "/").last ?? ""), isDir: false,
                         size: size, modTime: mod, keepState: keep)
    }

    private func folder(_ id: String) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: String(id.split(separator: "/").last ?? ""), isDir: true,
                         size: 0, modTime: nil, keepState: 0)
    }

    @Test func firstListingReportsEverythingAsNew() {
        let result = RemoteChangeDiff.diff(old: nil, new: [file("s3:a"), folder("s3:b")])
        #expect(result.changed == ["s3:a", "s3:b"])
        #expect(result.deleted.isEmpty)
        #expect(result.hasChanges)
    }

    @Test func identicalListingIsNoChange() {
        let listing = [file("s3:a"), folder("s3:b")]
        let result = RemoteChangeDiff.diff(old: listing, new: listing)
        #expect(!result.hasChanges)
    }

    @Test func addedFileIsChanged() {
        let result = RemoteChangeDiff.diff(old: [file("s3:a")], new: [file("s3:a"), file("s3:new.txt")])
        #expect(result.changed == ["s3:new.txt"])
        #expect(result.deleted.isEmpty)
    }

    @Test func editedFileIsChanged() {
        let bySize = RemoteChangeDiff.diff(old: [file("s3:a", size: 1)], new: [file("s3:a", size: 2)])
        #expect(bySize.changed == ["s3:a"])
        let byModTime = RemoteChangeDiff.diff(old: [file("s3:a", mod: 100)], new: [file("s3:a", mod: 200)])
        #expect(byModTime.changed == ["s3:a"])
        let byPin = RemoteChangeDiff.diff(old: [file("s3:a", keep: 0)], new: [file("s3:a", keep: 1)])
        #expect(byPin.changed == ["s3:a"])
    }

    @Test func renameIsDeleteAndAdd() {
        let result = RemoteChangeDiff.diff(old: [file("s3:bucket/old.txt")], new: [file("s3:bucket/new.txt")])
        #expect(result.changed == ["s3:bucket/new.txt"])
        #expect(result.deleted == ["s3:bucket/old.txt"])
        #expect(result.deletedFolders.isEmpty)
    }

    @Test func deletedFolderIsAlsoListedAsDeletedFolder() {
        let result = RemoteChangeDiff.diff(old: [folder("s3:bucket"), file("s3:x")], new: [file("s3:x")])
        #expect(result.deleted == ["s3:bucket"])
        #expect(result.deletedFolders == ["s3:bucket"])
    }

    @Test func duplicateIdentifiersDoNotCrashOrRepeat() {
        let result = RemoteChangeDiff.diff(old: [file("s3:a"), file("s3:a")], new: [file("s3:b"), file("s3:b")])
        #expect(result.changed == ["s3:b"])
        #expect(result.deleted == ["s3:a"])
    }

    @Test func foldersInListingAreTheNextLevel() {
        let listing = [folder("s3:b1"), file("s3:f"), folder("s3:b2"), folder("s3:b1")]
        #expect(RemoteChangeDiff.folders(in: listing) == ["s3:b1", "s3:b2"])
    }

    @Test func anchorRoundTrips() {
        let data = WorkingSetAnchor.encode(pinSequence: 42, remoteGeneration: 7)
        #expect(data.count == 24)
        let decoded = WorkingSetAnchor.decode(data)
        #expect(decoded.pinSequence == 42)
        #expect(decoded.remoteGeneration == 7)
        #expect(decoded.format == WorkingSetAnchor.currentFormat)
    }

    @Test func anchorFromTheEmptyListingBuildDecodesAsFormatZero() {
        var old = withUnsafeBytes(of: Int64(42).littleEndian) { Data($0) }
        old.append(withUnsafeBytes(of: Int64(7).littleEndian) { Data($0) })
        let decoded = WorkingSetAnchor.decode(old)
        #expect(decoded.pinSequence == 42)
        #expect(decoded.remoteGeneration == 7)
        #expect(decoded.format == 0)
        #expect(decoded.format < WorkingSetAnchor.currentFormat)
    }

    @Test func legacyPinOnlyAnchorDecodesWithGenerationZero() {
        let legacy = withUnsafeBytes(of: Int64(9).littleEndian) { Data($0) }
        let decoded = WorkingSetAnchor.decode(legacy)
        #expect(decoded.pinSequence == 9)
        #expect(decoded.remoteGeneration == 0)
        #expect(decoded.format == 0)
    }

    @Test func malformedAnchorDecodesAsZero() {
        let decoded = WorkingSetAnchor.decode(Data([1, 2, 3]))
        #expect(decoded.pinSequence == 0)
        #expect(decoded.remoteGeneration == 0)
    }
}

@Suite("RemoteChangeWalk")
struct RemoteChangeWalkTests {
    private static let root = "ROOT"

    private static func folder(_ id: String) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: id, isDir: true, size: 0, modTime: nil, keepState: 0)
    }

    private static func file(_ id: String) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: id, isDir: false, size: 1, modTime: 1, keepState: 0)
    }

    /// Server tree + which containers have a snapshot; visits record order.
    private final class Fake: @unchecked Sendable {
        let server: [String: [SyncedItemRecord]]
        let known: Set<String>
        let failing: Set<String>
        private let lock = NSLock()
        private(set) var listed: [String] = []

        init(server: [String: [SyncedItemRecord]], known: Set<String>, failing: Set<String> = []) {
            self.server = server
            self.known = known
            self.failing = failing
        }

        func visit(_ container: String) -> RemoteChangeVisit<Int>? {
            lock.withLock { listed.append(container) }
            guard !failing.contains(container) else { return nil }
            let listing = server[container] ?? []
            return RemoteChangeVisit(container: container, listing: listing,
                                     diff: RemoteChangeDiff.diff(old: [], new: listing), payload: listing.count)
        }
    }

    private func walk(_ fake: Fake, width: Int = 4) async -> [RemoteChangeVisit<Int>] {
        await RemoteChangeWalk.run(root: Self.root, isKnown: { fake.known.contains($0) }, width: width) {
            fake.visit($0)
        }
    }

    @Test func nothingKnownMeansNothingListed() async {
        let fake = Fake(server: [Self.root: [Self.file("a")]], known: [])
        #expect(await walk(fake).isEmpty)
        #expect(fake.listed.isEmpty)
    }

    @Test func walksOnlyKnownFoldersLevelByLevel() async {
        let fake = Fake(server: [
            Self.root: [Self.folder("b1"), Self.folder("b2"), Self.file("f")],
            "b1": [Self.folder("b1/x"), Self.folder("b1/never-opened")],
            "b1/x": [Self.file("b1/x/doc")],
            "b2": [],
        ], known: [Self.root, "b1", "b2", "b1/x"])
        let visits = await walk(fake, width: 1)
        #expect(visits.map(\.container) == [Self.root, "b1", "b2", "b1/x"])
        #expect(!fake.listed.contains("b1/never-opened"))
    }

    @Test func folderGoneFromTheServerIsNotWalkedInto() async {
        // "gone" still has a snapshot, but the root listing no longer has it.
        let fake = Fake(server: [Self.root: [Self.file("f")], "gone": [Self.file("gone/x")]],
                        known: [Self.root, "gone"])
        let visits = await walk(fake)
        #expect(visits.map(\.container) == [Self.root])
    }

    @Test func failedListingSkipsThatSubtreeOnly() async {
        let fake = Fake(server: [
            Self.root: [Self.folder("a"), Self.folder("b")],
            "a": [Self.folder("a/deep")],
            "a/deep": [],
            "b": [Self.file("b/f")],
        ], known: [Self.root, "a", "a/deep", "b"], failing: ["a"])
        let visits = await walk(fake)
        #expect(visits.map(\.container) == [Self.root, "b"])
        #expect(!fake.listed.contains("a/deep"))
    }

    @Test func resultsKeepLevelOrderWithParallelListing() async {
        let names = (0..<10).map { "d\($0)" }
        var server: [String: [SyncedItemRecord]] = [Self.root: names.map(Self.folder)]
        for name in names { server[name] = [] }
        let fake = Fake(server: server, known: Set(names + [Self.root]))
        let visits = await walk(fake, width: 3)
        #expect(visits.map(\.container) == [Self.root] + names)
    }
}

@Suite("WorkingSetListing")
struct WorkingSetListingTests {
    private static let root = "ROOT"

    private static func folder(_ id: String) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: id, isDir: true, size: 0, modTime: nil, keepState: 0)
    }

    private static func file(_ id: String) -> SyncedItemRecord {
        SyncedItemRecord(identifier: id, name: id, isDir: false, size: 1, modTime: 1, keepState: 0)
    }

    private func collect(_ snapshots: [String: [SyncedItemRecord]]) -> [WorkingSetListing.Entry] {
        WorkingSetListing.collect(root: Self.root) { snapshots[$0] }
    }

    @Test func nothingListedMeansNothingInTheWorkingSet() {
        #expect(collect([:]).isEmpty)
    }

    @Test func listsEveryEntryOfEveryListedFolderWithItsParent() {
        let entries = collect([
            Self.root: [Self.folder("a"), Self.file("f")],
            "a": [Self.file("a/doc"), Self.folder("a/b")],
            "a/b": [Self.file("a/b/deep")],
        ])
        #expect(entries.map(\.record.identifier) == ["a", "f", "a/doc", "a/b", "a/b/deep"])
        #expect(entries.map(\.parent) == [Self.root, Self.root, "a", "a", "a/b"])
    }

    @Test func folderNeverListedIsIncludedButNotEntered() {
        let entries = collect([
            Self.root: [Self.folder("opened"), Self.folder("never")],
            "opened": [Self.file("opened/x")],
            // A stale snapshot under an unlisted path is unreachable.
            "never/stale": [Self.file("never/stale/y")],
        ])
        #expect(entries.map(\.record.identifier) == ["opened", "never", "opened/x"])
    }

    @Test func snapshotNoLongerReachableFromTheRootIsLeftOut() {
        let entries = collect([Self.root: [Self.file("f")], "gone": [Self.file("gone/x")]])
        #expect(entries.map(\.record.identifier) == ["f"])
    }

    @Test func duplicatesAndCyclesAppearOnce() {
        let entries = collect([
            Self.root: [Self.folder("a"), Self.folder("a")],
            "a": [Self.folder("a"), Self.folder(Self.root), Self.file("a/x")],
        ])
        #expect(entries.map(\.record.identifier) == ["a", "a/x"])
    }
}
