import Foundation
import Testing
@testable import Nimbus

@Suite("DragDropCoordinator")
@MainActor
struct DragDropCoordinatorTests {
    private func makeRef(remote: String, path: String, size: Int64 = 1000) -> NimbusFileRef {
        NimbusFileRef(remoteName: remote, path: path, size: size, isDir: false)
    }

    @Test func dropOfSameRemoteResolvesToWithinRemote() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let refs = [makeRef(remote: "gdrive", path: "/Photos/a.jpg")]
        let intent = try coord.resolve(drop: refs, onto: .init(remote: "gdrive", path: "/Backup"))
        if case .withinRemote(let items, let dest, _) = intent {
            #expect(items.count == 1)
            #expect(dest == "/Backup")
        } else {
            Issue.record("Expected .withinRemote, got \(intent)")
        }
    }

    @Test func dropOfDifferentRemoteResolvesToCrossRemote() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let refs = [makeRef(remote: "gdrive", path: "/Photos/a.jpg")]
        let intent = try coord.resolve(drop: refs, onto: .init(remote: "s3", path: "/Backup"))
        if case .crossRemote(let items, let src, let target) = intent {
            #expect(items.count == 1)
            #expect(src == "gdrive")
            #expect(target.remote == "s3")
            #expect(target.path == "/Backup")
        } else {
            Issue.record("Expected .crossRemote, got \(intent)")
        }
    }

    @Test func mixedSourceRemotesThrowsError() {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let refs = [
            makeRef(remote: "gdrive", path: "/a.jpg"),
            makeRef(remote: "s3", path: "/b.jpg"),
        ]
        #expect(throws: DragDropError.self) {
            _ = try coord.resolve(drop: refs, onto: .init(remote: "dropbox", path: "/"))
        }
    }

    @Test func applyCrossRemoteWithFewItemsEnqueuesOnePerItem() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let intent: DropIntent = .crossRemote(
            items: [
                .init(name: "a.jpg", path: "/a.jpg", size: 100, isDir: false),
                .init(name: "b.jpg", path: "/b.jpg", size: 100, isDir: false),
            ],
            sourceRemote: "gdrive",
            target: .init(remote: "s3", path: "/Backup")
        )
        try await coord.apply(intent, conflictPolicy: .rename)

        #expect(client.copyFileCalls.count == 2)
        #expect(client.syncCopyCalls.isEmpty)
        #expect(store.transfers.count == 2)
        #expect(store.transfers.allSatisfy { $0.origin == .crossRemoteDrop })
    }

    @Test func applyCrossRemoteWithManyItemsBatchesIntoSyncCopy() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        // Items share a real common parent `/Photos`, so batching is safe.
        let items = (0..<10).map { i in
            DropIntent.Item(name: "\(i).jpg", path: "/Photos/\(i).jpg", size: 100, isDir: false)
        }
        let intent: DropIntent = .crossRemote(
            items: items,
            sourceRemote: "gdrive",
            target: .init(remote: "s3", path: "/Backup")
        )
        try await coord.apply(intent, conflictPolicy: .overwrite)

        #expect(client.copyFileCalls.isEmpty)
        #expect(client.syncCopyCalls.count == 1)
        #expect(store.transfers.count == 1)
        #expect(store.transfers[0].origin == .crossRemoteDrop)
    }

    @Test func applyWithinRemoteCallsMoveByDefault() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let intent: DropIntent = .withinRemote(
            items: [.init(name: "a.jpg", path: "/Pics/a.jpg", size: 100, isDir: false)],
            destPath: "/Archive",
            sourceRemote: "gdrive"
        )
        try await coord.apply(intent, conflictPolicy: .overwrite)

        #expect(client.moveFileCalls.count == 1)
        #expect(client.copyFileCalls.isEmpty)
    }

    @Test func applyCrossRemoteFewItemsWithRenameSetsSuffixFlag() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let intent: DropIntent = .crossRemote(
            items: [.init(name: "a.jpg", path: "/a.jpg", size: 100, isDir: false)],
            sourceRemote: "gdrive",
            target: .init(remote: "s3", path: "/Backup")
        )
        try await coord.apply(intent, conflictPolicy: .rename)

        #expect(client.copyFileCalls.count == 1)
        let suffix = client.copyFileCalls[0].flags["suffix"]
        #expect(suffix != nil)
        #expect(suffix?.hasPrefix("_conflict-") == true)
    }

    @Test func applyCrossRemoteMixedParentsFallsBackToPerItemCopy() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        // 10 items from two different parents → batching would target root `/`.
        // Should fall back to per-item copyfile.
        let items = (0..<5).map { i in
            DropIntent.Item(name: "a\(i).jpg", path: "/A/a\(i).jpg", size: 100, isDir: false)
        } + (0..<5).map { i in
            DropIntent.Item(name: "b\(i).jpg", path: "/B/b\(i).jpg", size: 100, isDir: false)
        }
        let intent: DropIntent = .crossRemote(
            items: items,
            sourceRemote: "gdrive",
            target: .init(remote: "s3", path: "/Backup")
        )
        try await coord.apply(intent, conflictPolicy: .overwrite)

        // Critical: NO sync/copy call (root-level sync would be catastrophic)
        #expect(client.syncCopyCalls.isEmpty)
        // 10 individual copyfile calls
        #expect(client.copyFileCalls.count == 10)
    }

    @Test func applyCrossRemoteSharedParentBatchesIntoSyncCopy() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let items = (0..<10).map { i in
            DropIntent.Item(name: "\(i).jpg", path: "/Photos/\(i).jpg", size: 100, isDir: false)
        }
        let intent: DropIntent = .crossRemote(
            items: items,
            sourceRemote: "gdrive",
            target: .init(remote: "s3", path: "/Backup")
        )
        try await coord.apply(intent, conflictPolicy: .skip)

        // Real common parent → does batch into sync/copy with the conflict flag.
        #expect(client.syncCopyCalls.count == 1)
        let syncCall = client.syncCopyCalls[0]
        #expect(syncCall.src == "gdrive:/Photos")
        #expect(syncCall.flags["ignore-existing"] == "true")
    }

    @Test func applyWithinRemoteRecordsOperationAsMove() async throws {
        let store = TransferStore()
        let client = RecordingRcloneClient()
        let coord = DragDropCoordinator(transferStore: store, rclone: client)

        let intent: DropIntent = .withinRemote(
            items: [.init(name: "a.jpg", path: "/Pics/a.jpg", size: 100, isDir: false)],
            destPath: "/Archive",
            sourceRemote: "gdrive"
        )
        try await coord.apply(intent, conflictPolicy: .overwrite)

        #expect(store.transfers.count == 1)
        #expect(store.transfers[0].operation == .move)
    }
}

// MARK: - Recording stub

@MainActor
private final class RecordingRcloneClient: DragDropCoordinator.RcloneInterface {
    var copyFileCalls: [(src: String, srcPath: String, dst: String, dstPath: String, flags: [String: String])] = []
    var moveFileCalls: [(src: String, srcPath: String, dst: String, dstPath: String)] = []
    var syncCopyCalls: [(src: String, dst: String, flags: [String: String])] = []
    private var nextJobID = 1000

    func operationsCopyFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        flags: [String: String]
    ) async throws -> Int {
        copyFileCalls.append((srcFs, srcRemote, dstFs, dstRemote, flags))
        defer { nextJobID += 1 }
        return nextJobID
    }

    func operationsMoveFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws -> Int {
        moveFileCalls.append((srcFs, srcRemote, dstFs, dstRemote))
        defer { nextJobID += 1 }
        return nextJobID
    }

    func syncCopy(srcFs: String, dstFs: String, flags: [String: String]) async throws -> Int {
        syncCopyCalls.append((srcFs, dstFs, flags))
        defer { nextJobID += 1 }
        return nextJobID
    }
}
