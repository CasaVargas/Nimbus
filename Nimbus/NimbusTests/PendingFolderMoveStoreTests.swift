import Foundation
import Testing
@testable import Nimbus

@Suite("PendingFolderMoveStore")
struct PendingFolderMoveStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PendingFolderMoveStoreTests-\(UUID().uuidString)", isDirectory: true)

    @Test func beginAndFinishTrackResolvedDestination() throws {
        let store = PendingFolderMoveStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_763_711_880)

        #expect(store.pendingDestination(from: "Work", requested: "Archive", domain: "gdrive", now: now) == nil)
        try store.begin(from: "Work", requested: "Archive", resolved: "Archive 2", domain: "gdrive", now: now)
        #expect(store.pendingDestination(from: "Work", requested: "Archive", domain: "gdrive", now: now) == "Archive 2")
        #expect(store.pendingDestination(from: "Work", requested: "Archive", domain: "onedrive", now: now) == nil)

        try store.finish(from: "Work", requested: "Archive", domain: "gdrive")
        #expect(store.pendingDestination(from: "Work", requested: "Archive", domain: "gdrive", now: now) == nil)
    }

    @Test func entriesExpireAfterMaxAge() throws {
        let store = PendingFolderMoveStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_763_711_880)
        let maxAge: TimeInterval = 7 * 24 * 3600

        try store.begin(from: "A", requested: "B", resolved: "B 2", domain: "s3", now: start)
        #expect(store.pendingDestination(
            from: "A", requested: "B", domain: "s3",
            now: start.addingTimeInterval(maxAge - 1), maxAge: maxAge
        ) == "B 2")
        #expect(store.pendingDestination(
            from: "A", requested: "B", domain: "s3",
            now: start.addingTimeInterval(maxAge), maxAge: maxAge
        ) == nil)
    }

    @Test func entriesSurviveAFreshStoreInstance() throws {
        let now = Date(timeIntervalSince1970: 1_763_711_880)
        try PendingFolderMoveStore(directory: directory)
            .begin(from: "Photos", requested: "Pictures", resolved: "Pictures 3", domain: "s3", now: now)
        #expect(PendingFolderMoveStore(directory: directory)
            .pendingDestination(from: "Photos", requested: "Pictures", domain: "s3", now: now) == "Pictures 3")
    }

    @Test func oldShapeFileDecodesAsEmptyAndIsReplacedOnNextBegin() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("s3.json")
        let oldJSON = #"[{"from":"A","to":"B","startedAt":1763711880}]"#
        try Data(oldJSON.utf8).write(to: fileURL, options: .atomic)

        let now = Date(timeIntervalSince1970: 1_763_711_880)
        let store = PendingFolderMoveStore(directory: directory)
        #expect(store.pendingDestination(from: "A", requested: "B", domain: "s3", now: now) == nil)

        try store.begin(from: "A", requested: "B", resolved: "B 2", domain: "s3", now: now)
        #expect(store.pendingDestination(from: "A", requested: "B", domain: "s3", now: now) == "B 2")
        #expect(PendingFolderMoveStore(directory: directory)
            .pendingDestination(from: "A", requested: "B", domain: "s3", now: now) == "B 2")
    }

    @Test func secondBeginReplacesSameSourceAndFinishClearsBySource() throws {
        let store = PendingFolderMoveStore(directory: directory)
        let t0 = Date(timeIntervalSince1970: 1_763_711_880)
        let t1 = t0.addingTimeInterval(600)
        let maxAge = PendingFolderMoveStore.defaultMaxAge

        // Re-beginning the same (from, requested) updates resolved and startedAt in place.
        try store.begin(from: "A", requested: "B", resolved: "B 2", domain: "s3", now: t0)
        try store.begin(from: "A", requested: "B", resolved: "B 3", domain: "s3", now: t1)
        #expect(store.pendingDestination(
            from: "A", requested: "B", domain: "s3",
            now: t0.addingTimeInterval(maxAge + 10), maxAge: maxAge
        ) == "B 3")

        // A second begin for the same source with a different requested destination replaces the first.
        try store.begin(from: "A", requested: "C", resolved: "C 2", domain: "s3", now: t1)
        #expect(store.pendingDestination(from: "A", requested: "B", domain: "s3", now: t1) == nil)
        #expect(store.pendingDestination(from: "A", requested: "C", domain: "s3", now: t1) == "C 2")

        // Finishing with a different requested destination still clears the source entry.
        try store.finish(from: "A", requested: "B", domain: "s3")
        #expect(store.pendingDestination(from: "A", requested: "C", domain: "s3", now: t1) == nil)
    }

    @Test func writesPruneExpiredEntriesAndSpecialDomainNamesRoundTrip() throws {
        let store = PendingFolderMoveStore(directory: directory)
        let t0 = Date(timeIntervalSince1970: 1_763_711_880)
        let afterExpiry = t0.addingTimeInterval(PendingFolderMoveStore.defaultMaxAge + 1)
        let domain = "my cloud/s3:prod"

        try store.begin(from: "Old", requested: "OldDst", resolved: "OldDst", domain: domain, now: t0)
        try store.begin(from: "Fresh", requested: "FreshDst", resolved: "FreshDst 2", domain: domain, now: afterExpiry)

        // Old entry was pruned on disk when Fresh was written, so even querying at t0 returns nil.
        let freshInstance = PendingFolderMoveStore(directory: directory)
        #expect(freshInstance.pendingDestination(from: "Old", requested: "OldDst", domain: domain, now: t0) == nil)
        #expect(freshInstance.pendingDestination(from: "Fresh", requested: "FreshDst", domain: domain, now: afterExpiry) == "FreshDst 2")

        try freshInstance.finish(from: "Fresh", requested: "FreshDst", domain: domain)
        #expect(PendingFolderMoveStore(directory: directory)
            .pendingDestination(from: "Fresh", requested: "FreshDst", domain: domain, now: afterExpiry) == nil)
    }
}
