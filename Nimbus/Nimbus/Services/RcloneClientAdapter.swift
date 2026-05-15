import Foundation
import RcloneKit

/// Production-side adapter that satisfies `RcloneClientProtocol` by delegating
/// to `RcloneKit.RcloneClient`. Marked `@unchecked Sendable` because
/// `RcloneClient` itself vouches for its thread-safety (its port is only
/// mutated from MainActor during startup; HTTP calls are otherwise safe).
final class RcloneClientAdapter: RcloneClientProtocol, @unchecked Sendable {
    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func downloadToTemp(remote: String, path: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-quicklook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let filename = (path as NSString).lastPathComponent
        let dstURL = tempDir.appendingPathComponent(filename)

        // rclone operations/copyfile params:
        //   srcFs      = "remote:"           filesystem prefix (trailing colon required)
        //   srcRemote  = path                rclone-relative path from the remote root
        //   dstFs      = tempDir.path + "/"  local filesystem (trailing slash for rclone)
        //   dstRemote  = filename            leaf name only
        try await client.copyFile(
            srcFs: "\(remote):",
            srcRemote: path,
            dstFs: tempDir.path + "/",
            dstRemote: filename
        )
        return dstURL
    }
}

// MARK: - DragDropCoordinator.RcloneInterface

@MainActor
extension RcloneClientAdapter: DragDropCoordinator.RcloneInterface {
    func operationsCopyFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String,
        flags: [String: String]
    ) async throws -> Int {
        try await client.copyFileAsync(
            srcFs: srcFs, srcRemote: srcRemote,
            dstFs: dstFs, dstRemote: dstRemote,
            extraParams: flags
        )
    }

    func operationsMoveFile(
        srcFs: String, srcRemote: String,
        dstFs: String, dstRemote: String
    ) async throws -> Int {
        try await client.moveFileAsync(
            srcFs: srcFs, srcRemote: srcRemote,
            dstFs: dstFs, dstRemote: dstRemote
        )
    }

    /// Note: ignores `flags` for now — the existing `RcloneClient.copy(srcFs:dstFs:)`
    /// doesn't accept extra params. If Phase 1 needs flag support for sync/copy,
    /// add a `copyWithFlags` variant in RcloneKit.
    func syncCopy(srcFs: String, dstFs: String, flags: [String: String]) async throws -> Int {
        try await client.copy(srcFs: srcFs, dstFs: dstFs)
    }
}
