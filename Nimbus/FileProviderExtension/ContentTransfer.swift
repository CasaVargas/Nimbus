import Foundation
import RcloneKit
import os

/// How file contents travel between Finder and a cloud.
///
/// The fast way is direct: the file is staged in the app group container
/// (`TransferStaging`) and the rclone daemon copies it itself. An upload's
/// size is then known up front, so a cloud without streaming uploads
/// (OneDrive) receives it straight away instead of after rclone has spooled
/// the stream to a second temporary file; a large download arrives over
/// several connections; and no part of the file is held in this process's
/// memory.
///
/// The other way pushes the bytes through the daemon's HTTP API
/// (`downloadFile` / `uploadFile`). It needs nothing but the network, so it
/// stays as the fallback for a daemon that can't reach the staging folder.
enum ContentTransfer {
    /// Set once a probe file has made the round trip through the daemon.
    /// A failed probe isn't remembered: the daemon may just not be up yet,
    /// and asking again costs the next transfer one small request.
    private static let directConfirmed = OSAllocatedUnfairLock(initialState: false)

    // MARK: Download

    /// Fetches `remotePath` into `destination`, replacing anything there.
    static func download(
        rclone: RcloneClient,
        remoteName: String,
        remotePath: String,
        to destination: URL,
        progress: Progress,
        logger: Logger
    ) async throws {
        guard let container = await stagingContainer(rclone: rclone, logger: logger) else {
            try await rclone.downloadFile(fs: "\(remoteName):", remote: remotePath, to: destination)
            return
        }
        let folder = try TransferStaging.makeFolder(in: container)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = TransferStaging.stagedName(for: (remotePath as NSString).lastPathComponent)

        try await rclone.copyFileAndWait(
            srcFs: "\(remoteName):", srcRemote: remotePath,
            dstFs: stagingFs(in: container), dstRemote: stagedRemote(name, in: folder)
        ) { bytes in
            AppWaker.ping()
            report(bytes, on: progress)
        }

        // Out of the shared folder and into our own container, where the
        // system has always picked downloads up. Same volume: a rename.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: folder.appendingPathComponent(name), to: destination)
    }

    // MARK: Upload

    /// Sends the file at `localURL` to `directory/filename` on the remote.
    static func upload(
        rclone: RcloneClient,
        from localURL: URL,
        remoteName: String,
        directory: String,
        filename: String,
        progress: Progress,
        logger: Logger
    ) async throws {
        guard let container = await stagingContainer(rclone: rclone, logger: logger) else {
            try await rclone.uploadFile(from: localURL, fs: "\(remoteName):", remote: directory, filename: filename)
            return
        }
        let folder = try TransferStaging.makeFolder(in: container)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = TransferStaging.stagedName(for: filename)

        // The daemon can't open the system's staging file where it is. On
        // APFS this copy is a clone: nothing is read or written, and the
        // file takes no extra space.
        try FileManager.default.copyItem(at: localURL, to: folder.appendingPathComponent(name))

        try await rclone.copyFileAndWait(
            srcFs: stagingFs(in: container), srcRemote: stagedRemote(name, in: folder),
            dstFs: "\(remoteName):", dstRemote: directory.isEmpty ? filename : "\(directory)/\(filename)"
        ) { bytes in
            AppWaker.ping()
            report(bytes, on: progress)
            // rclone only reads here, so nothing else tells the sweep that
            // a day-long upload is still alive.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
        }
    }

    // MARK: Direct path

    /// The app group container, if the daemon can exchange files with this
    /// process through it.
    private static func stagingContainer(rclone: RcloneClient, logger: Logger) async -> URL? {
        guard let container = AppGroup.containerURL else { return nil }
        if directConfirmed.withLock({ $0 }) { return container }
        guard await probe(rclone: rclone, container: container, logger: logger) else { return nil }
        directConfirmed.withLock { $0 = true }
        return container
    }

    /// Has the daemon copy a file this process wrote, then reads the copy
    /// back: both sides can read what the other writes.
    private static func probe(rclone: RcloneClient, container: URL, logger: Logger) async -> Bool {
        do {
            let folder = try TransferStaging.makeFolder(in: container)
            defer { try? FileManager.default.removeItem(at: folder) }
            let token = Data(UUID().uuidString.utf8)
            try token.write(to: folder.appendingPathComponent("probe"))
            let fs = stagingFs(in: container)
            try await rclone.copyFile(
                srcFs: fs, srcRemote: stagedRemote("probe", in: folder),
                dstFs: fs, dstRemote: stagedRemote("echo", in: folder)
            )
            return try Data(contentsOf: folder.appendingPathComponent("echo")) == token
        } catch {
            logger.info("Direct transfers unavailable, using HTTP: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// What rclone is given as the local side of a copy: always the staging
    /// root, with the transfer's folder in the path. One name for the
    /// daemon to keep a filesystem open for, not one per transfer.
    private static func stagingFs(in container: URL) -> String {
        TransferStaging.root(in: container).path
    }

    private static func stagedRemote(_ name: String, in folder: URL) -> String {
        "\(folder.lastPathComponent)/\(name)"
    }

    /// Moves `progress` to `bytes`, stopping one short of the total: the
    /// caller completes it once the item itself is confirmed. A total of 1
    /// means the size isn't known.
    private static func report(_ bytes: Int64, on progress: Progress) {
        let total = progress.totalUnitCount
        guard total > 1 else { return }
        progress.completedUnitCount = min(max(bytes, 0), total - 1)
    }
}
