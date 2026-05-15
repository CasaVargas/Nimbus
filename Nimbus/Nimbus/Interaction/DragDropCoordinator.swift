import Foundation
import Observation

/// How to handle name collisions at the destination when applying a drop.
enum ConflictPolicy: String, Sendable {
    case rename
    case skip
    case overwrite
}

/// A resolved drop operation that the coordinator has classified by direction
/// and inferred shape. Built by `DragDropCoordinator.resolve(drop:onto:)`
/// before being executed via `apply(_:conflictPolicy:)`.
enum DropIntent: Sendable {
    case withinRemote(items: [Item], destPath: String, sourceRemote: String)
    case crossRemote(items: [Item], sourceRemote: String, target: DropTarget)
    case toFinder(items: [Item])

    struct Item: Sendable, Hashable {
        let name: String
        let path: String
        let size: Int64
        let isDir: Bool
    }

    struct DropTarget: Sendable, Hashable {
        let remote: String
        let path: String
    }
}

/// Coordinates drag-and-drop operations inside Nimbus.
///
/// Responsibilities:
/// - Classify a set of dropped `NimbusFileRef`s onto a target into a `DropIntent`.
/// - Translate the intent into rclone RC API calls (`operations/copyfile`,
///   `operations/movefile`, or batched `sync/copy`).
/// - Register each enqueued job with `TransferStore` tagged by `TransferOrigin`.
@MainActor
@Observable
final class DragDropCoordinator {
    /// Test seam: the subset of rclone operations the coordinator needs.
    /// Production conformance lives on `RcloneClientAdapter`; tests substitute
    /// a recording double.
    @MainActor
    protocol RcloneInterface: AnyObject {
        func operationsCopyFile(
            srcFs: String, srcRemote: String,
            dstFs: String, dstRemote: String,
            flags: [String: String]
        ) async throws -> Int
        func operationsMoveFile(
            srcFs: String, srcRemote: String,
            dstFs: String, dstRemote: String
        ) async throws -> Int
        func syncCopy(
            srcFs: String, dstFs: String,
            flags: [String: String]
        ) async throws -> Int
    }

    /// Above this many items, a cross-remote drop is batched into a single
    /// `sync/copy` job over the items' common prefix instead of N per-file jobs.
    static let batchThreshold = 5

    private let transferStore: TransferStore
    private let rclone: RcloneInterface

    init(transferStore: TransferStore, rclone: RcloneInterface) {
        self.transferStore = transferStore
        self.rclone = rclone
    }

    /// Classifies a set of dropped `NimbusFileRef`s against a destination.
    ///
    /// - Returns `.withinRemote` when every ref shares the same source remote
    ///   AND that remote equals the target remote — this becomes an
    ///   `operations/movefile` per item.
    /// - Returns `.crossRemote` otherwise (including mixed-source drops). The
    ///   first ref's remote is treated as the canonical source. Mixed-source
    ///   drops should be rare in practice; the API call uses one source remote.
    func resolve(drop refs: [NimbusFileRef], onto target: DropIntent.DropTarget) -> DropIntent {
        guard let first = refs.first else { return .toFinder(items: []) }
        let items = refs.map { ref in
            DropIntent.Item(
                name: (ref.path as NSString).lastPathComponent,
                path: ref.path,
                size: ref.size,
                isDir: ref.isDir
            )
        }

        let allSameRemote = refs.allSatisfy { $0.remoteName == first.remoteName }
        if allSameRemote && first.remoteName == target.remote {
            return .withinRemote(items: items, destPath: target.path, sourceRemote: first.remoteName)
        }
        return .crossRemote(items: items, sourceRemote: first.remoteName, target: target)
    }

    /// Executes the intent: enqueues rclone jobs and registers each one with
    /// `TransferStore` so progress UI can pick them up.
    func apply(_ intent: DropIntent, conflictPolicy: ConflictPolicy) async throws {
        switch intent {
        case .withinRemote(let items, let destPath, let sourceRemote):
            for item in items {
                let dstPath = "\(destPath)/\(item.name)"
                let jobId = try await rclone.operationsMoveFile(
                    srcFs: "\(sourceRemote):",
                    srcRemote: item.path,
                    dstFs: "\(sourceRemote):",
                    dstRemote: dstPath
                )
                transferStore.addTransfer(
                    jobId: jobId,
                    operation: .copy,
                    srcFs: "\(sourceRemote):\(item.path)",
                    dstFs: "\(sourceRemote):\(dstPath)",
                    origin: .manual
                )
            }

        case .crossRemote(let items, let sourceRemote, let target):
            if items.count <= Self.batchThreshold {
                for item in items {
                    let dstPath = "\(target.path)/\(item.name)"
                    let jobId = try await rclone.operationsCopyFile(
                        srcFs: "\(sourceRemote):",
                        srcRemote: item.path,
                        dstFs: "\(target.remote):",
                        dstRemote: dstPath,
                        flags: flagsFor(conflictPolicy)
                    )
                    transferStore.addTransfer(
                        jobId: jobId,
                        operation: .copy,
                        srcFs: "\(sourceRemote):\(item.path)",
                        dstFs: "\(target.remote):\(dstPath)",
                        origin: .crossRemoteDrop
                    )
                }
            } else {
                let prefix = commonPrefix(items: items)
                let jobId = try await rclone.syncCopy(
                    srcFs: "\(sourceRemote):\(prefix)",
                    dstFs: "\(target.remote):\(target.path)",
                    flags: flagsFor(conflictPolicy)
                )
                transferStore.addTransfer(
                    jobId: jobId,
                    operation: .sync,
                    srcFs: "\(sourceRemote):\(prefix)",
                    dstFs: "\(target.remote):\(target.path)",
                    origin: .crossRemoteDrop
                )
            }

        case .toFinder:
            // SwiftUI's `Transferable` URL representation materializes bytes
            // for Finder drops; there's nothing to enqueue via the RC API.
            break
        }
    }

    /// Maps a `ConflictPolicy` to the corresponding rclone flags.
    private func flagsFor(_ policy: ConflictPolicy) -> [String: String] {
        switch policy {
        case .rename:
            return ["suffix": "_conflict-\(Int(Date().timeIntervalSince1970))"]
        case .skip:
            return ["ignore-existing": "true"]
        case .overwrite:
            return [:]
        }
    }

    /// Returns the deepest directory all items share, or "/" if they diverge.
    /// Used to scope a batched `sync/copy` over only the relevant subtree.
    private func commonPrefix(items: [DropIntent.Item]) -> String {
        guard let first = items.first else { return "" }
        let firstDir = (first.path as NSString).deletingLastPathComponent
        let allShared = items.allSatisfy { ($0.path as NSString).deletingLastPathComponent == firstDir }
        return allShared ? firstDir : "/"
    }
}
