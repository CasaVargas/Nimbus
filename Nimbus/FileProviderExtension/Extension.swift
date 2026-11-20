import FileProvider
import RcloneKit
import os
import UniformTypeIdentifiers

struct SendableBox<T>: @unchecked Sendable {
    let value: T
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    let rclone: RcloneClient
    let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "extension")
    /// Thumbnail downloads for this cloud, at most three at a time.
    let thumbnailLimiter = AsyncLimiter(limit: 3)
    /// This instance's own staging folder for downloads and thumbnail
    /// sources (`StagingArea.makeInstanceFolder()`).
    let stagingFolder: URL

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let (port, credentials) = FileProviderRetry.readConnection()
        self.rclone = RcloneClient(port: port, credentials: credentials)
        self.stagingFolder = StagingArea.shared.makeInstanceFolder()
        logger.error("Extension init: domain=\(domain.identifier.rawValue), port=\(port)")
        // Staged transfers an earlier, killed process left behind.
        if let container = AppGroup.containerURL {
            Task.detached(priority: .utility) { TransferStaging.sweep(in: container) }
        }
        StagingArea.removeOrphansOnce()
    }

    /// Re-reads the port from app group UserDefaults — the main app may have
    /// restarted on a different port since this extension process was spawned.
    func refreshPort() {
        FileProviderRetry.refreshPort(on: rclone, logger: logger)
    }

    func invalidate() {
        // Required by `NSFileProviderReplicatedExtension`. Removes only this
        // instance's folder, so other live instances of the same domain are
        // unaffected. A file just handed to `fetchContents`' completion
        // handler but not yet taken by the system is lost and that download
        // fails, which is accepted. Crash leftovers are removed at startup.
        try? FileManager.default.removeItem(at: stagingFolder)
    }

    // MARK: - Item Lookup

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        refreshPort()

        if identifier == .rootContainer {
            completionHandler(FileProviderItem.rootContainer(domain: domain), nil)
            return Progress()
        }

        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let progress = Progress(totalUnitCount: 1)

        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                let item = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "item(for:)") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: identifier, remoteName: remoteName)
                }
                progress.completedUnitCount = 1
                handler.value(item, nil)
            } catch {
                logger.error("item(for:) failed: \(error)")
                handler.value(nil, Self.mapToFileProviderError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        refreshPort()

        // `.workingSet` and `.trashContainer` are synthetic system
        // containers, not real rclone paths — see `SystemContainerEnumerator`
        // for why they're always empty.
        if containerItemIdentifier == .workingSet {
            let rclone = self.rclone
            let remoteName = domain.identifier.rawValue
            let logger = self.logger
            return WorkingSetEnumerator(domain: domain, fetchItem: { identifier in
                try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "workingSet.item", wakesApp: false) {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: identifier, remoteName: remoteName)
                }
            }, listFiles: { path in
                // Two tries, not the full ladder: a folder deleted on the
                // server fails here on some backends, and its parent's diff
                // already reports the deletion.
                try await FileProviderRetry.withReadRetry(
                    rclone: rclone, logger: logger, operation: "workingSet.scan", maxAttempts: 2,
                    wakesApp: false
                ) {
                    try await rclone.listFiles(fs: "\(remoteName):", remote: path)
                }
            })
        }
        if containerItemIdentifier == .trashContainer {
            return SystemContainerEnumerator(containerIdentifier: containerItemIdentifier)
        }

        return FileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            rclone: rclone,
            domain: domain
        )
    }

    // MARK: - Download

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        refreshPort()
        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let remotePath = Self.extractPathStatic(from: itemIdentifier, remoteName: remoteName)
        let stagingFolder = self.stagingFolder
        // Opening a file makes its folder hot: checked for remote changes
        // more often for a while (#76).
        HotFolderStore.touchParent(remoteName: remoteName, of: itemIdentifier)

        let progress = Progress(totalUnitCount: 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()

                // Fetch metadata first so we know the transfer size up front
                // (for progress) and can hand Finder the current item
                // alongside the bytes without a second round trip.
                let item = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "fetchContents.stat") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: itemIdentifier, remoteName: remoteName)
                }
                if let size = item.documentSize?.int64Value, size > 0 {
                    progress.totalUnitCount = size
                }

                // `NSTemporaryDirectory()` resolves inside the extension's own
                // sandbox container, which the rclone daemon can't write
                // to. `ContentTransfer` gets the bytes here either way: the
                // daemon downloads into the app group container and the
                // file is moved over, or (the fallback) they are streamed
                // over HTTP and this process writes them.
                let downloadDir = stagingFolder.appendingPathComponent("Downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

                let filename = (remotePath as NSString).lastPathComponent
                let localURL = downloadDir.appendingPathComponent(
                    "\(UUID().uuidString)_\(TransferStaging.stagedName(for: filename))")

                // The system only unlinks files it was handed, so a failed or
                // cancelled download must not leave its staged file behind.
                var handedOver = false
                defer {
                    if !handedOver { try? FileManager.default.removeItem(at: localURL) }
                }

                try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "fetchContents.download") {
                    try await ContentTransfer.download(
                        rclone: rclone, remoteName: remoteName, remotePath: remotePath,
                        to: localURL, progress: progress, logger: logger
                    )
                }
                try Task.checkCancellation()

                progress.completedUnitCount = progress.totalUnitCount
                handedOver = true
                handler.value(localURL, item, nil)
            } catch {
                logger.error("fetchContents failed: \(error)")
                handler.value(nil, nil, Self.mapToFileProviderError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Create

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        refreshPort()
        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let parentPath = Self.extractPathStatic(from: itemTemplate.parentItemIdentifier, remoteName: remoteName)
        HotFolderStore.touch(remoteName: remoteName, container: itemTemplate.parentItemIdentifier)
        let filename = itemTemplate.filename
        let isFolder = itemTemplate.contentType?.conforms(to: .directory) ?? false
        let localURL = url
        let domainBox = SendableBox(value: domain)

        let progress = Progress(totalUnitCount: Self.fileSizeOnDisk(localURL, orDefault: 1))
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                let newPath = parentPath.isEmpty ? filename : "\(parentPath)/\(filename)"

                if isFolder {
                    try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "createItem.mkdir") { _ in
                        try await rclone.createFolder(fs: "\(remoteName):", remote: newPath)
                    }
                } else if let localURL {
                    // rclone can't read the system-staged `localURL` where
                    // it is, so `ContentTransfer` clones it into the app
                    // group container for the daemon to upload, or (the
                    // fallback) sends the bytes over HTTP. The destination
                    // filename is passed explicitly since `localURL` isn't
                    // guaranteed to be named `filename`.
                    let identifier = "\(remoteName):\(newPath)"
                    do {
                        try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "createItem.upload") { _ in
                            try await ContentTransfer.upload(
                                rclone: rclone, from: localURL, remoteName: remoteName,
                                directory: parentPath, filename: filename,
                                progress: progress, logger: logger
                            )
                        }
                    } catch {
                        await UploadFailureReporting.failed(error, identifier: identifier, domain: domainBox.value, logger: logger)
                        throw error
                    }
                    UploadFailureReporting.succeeded([identifier], remoteName: remoteName, logger: logger)
                }

                let item = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "createItem.stat") {
                    try await Self.fetchItemStatic(
                        rclone: rclone,
                        identifier: NSFileProviderItemIdentifier("\(remoteName):\(newPath)"),
                        remoteName: remoteName
                    )
                }
                progress.completedUnitCount = progress.totalUnitCount
                handler.value(item, [], false, nil)
            } catch {
                logger.error("createItem failed: \(error)")
                handler.value(nil, [], false, Self.mapToFileProviderError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Modify

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        refreshPort()
        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let currentPath = Self.extractPathStatic(from: item.itemIdentifier, remoteName: remoteName)
        let newParentPath = Self.extractPathStatic(from: item.parentItemIdentifier, remoteName: remoteName)
        HotFolderStore.touch(remoteName: remoteName, container: item.parentItemIdentifier)
        let newFilename = item.filename
        let isDirectory = item.contentType?.conforms(to: .directory) ?? false
        let isRenameOrMove = changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier)
        let hasContentsChange = changedFields.contains(.contents)
        let contentsURL = newContents
        let systemIdentifier = item.itemIdentifier.rawValue
        let domainBox = SendableBox(value: domain)

        let progress = Progress(totalUnitCount: hasContentsChange ? Self.fileSizeOnDisk(contentsURL, orDefault: 1) : 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                var workingPath = currentPath

                if isRenameOrMove {
                    let destinationPath = newParentPath.isEmpty ? newFilename : "\(newParentPath)/\(newFilename)"
                    if destinationPath != currentPath {
                        try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.move") { isRetry in
                            if isRetry, try await Self.alreadyMoved(
                                rclone: rclone, remoteName: remoteName,
                                from: currentPath, to: destinationPath
                            ) {
                                return
                            }
                            let onMoveProgress: @Sendable (StatsResponse) -> Void = { stats in
                                if !hasContentsChange {
                                    Self.reportJobProgress(stats, on: progress)
                                }
                            }
                            if isDirectory {
                                // rclone has no "rename a directory" RC verb —
                                // `operations/movefile` only moves individual
                                // files — so directory renames/moves go
                                // through `sync/move` treating both the
                                // current and destination paths as directory
                                // roots (the `rclone move <src> <dst>` CLI
                                // command's RC equivalent).
                                try await rclone.moveDirectoryAndWait(
                                    srcFs: "\(remoteName):\(currentPath)",
                                    dstFs: "\(remoteName):\(destinationPath)",
                                    onProgress: onMoveProgress
                                )
                            } else {
                                try await rclone.moveFileAndWait(
                                    srcFs: "\(remoteName):", srcRemote: currentPath,
                                    dstFs: "\(remoteName):", dstRemote: destinationPath,
                                    onProgress: onMoveProgress
                                )
                            }
                        }
                        workingPath = destinationPath
                        try? PinStore.shared?.moved(
                            from: "\(remoteName):\(currentPath)", to: "\(remoteName):\(destinationPath)",
                            domain: remoteName)
                        try? UploadFailureStore.shared?.moved(
                            from: "\(remoteName):\(currentPath)", to: "\(remoteName):\(destinationPath)",
                            domain: remoteName)
                    }
                }

                if hasContentsChange, let contentsURL {
                    let uploadDir = (workingPath as NSString).deletingLastPathComponent
                    let uploadFilename = (workingPath as NSString).lastPathComponent
                    do {
                        try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.upload") { _ in
                            try await ContentTransfer.upload(
                                rclone: rclone, from: contentsURL, remoteName: remoteName,
                                directory: uploadDir, filename: uploadFilename,
                                progress: progress, logger: logger
                            )
                        }
                    } catch {
                        // Under the identifier the system knows: after a
                        // rename in this same call, the new one isn't its yet.
                        await UploadFailureReporting.failed(error, identifier: systemIdentifier,
                                                            domain: domainBox.value, logger: logger)
                        throw error
                    }
                    UploadFailureReporting.succeeded([systemIdentifier, "\(remoteName):\(workingPath)"],
                                                     remoteName: remoteName, logger: logger)
                }

                let newIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(workingPath)")
                let resultItem = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "modifyItem.stat") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: newIdentifier, remoteName: remoteName)
                }
                progress.completedUnitCount = progress.totalUnitCount
                handler.value(resultItem, [], false, nil)
            } catch {
                logger.error("modifyItem failed: \(error)")
                handler.value(nil, [], false, Self.mapToFileProviderError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Delete

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        refreshPort()
        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let remotePath = Self.extractPathStatic(from: identifier, remoteName: remoteName)
        HotFolderStore.touchParent(remoteName: remoteName, of: identifier)

        let progress = Progress(totalUnitCount: 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                do {
                    try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "deleteItem") { _ in
                        // `deleteItem` only gets an identifier — a path — not the
                        // `NSFileProviderItem`, so directory-ness comes from
                        // `operations/stat` (`rclone.item`) right before
                        // deleting: a missing path returns `nil` (already
                        // deleted remotely, which counts as success), folders
                        // go through `operations/purge` as a job, and files go
                        // through `operations/deletefile`.
                        guard let item = try await rclone.item(fs: "\(remoteName):", remote: remotePath) else {
                            return
                        }
                        if item.isDir {
                            try await rclone.purgeAndWait(fs: "\(remoteName):", remote: remotePath) { stats in
                                Self.reportJobProgress(stats, on: progress)
                            }
                        } else {
                            try await rclone.deleteFile(fs: "\(remoteName):", remote: remotePath)
                        }
                    }
                } catch RcloneError.requestFailed(status: 404, _) {
                    // The item vanished between the lookup and the delete call.
                }
                try? PinStore.shared?.removed(identifier.rawValue, domain: remoteName)
                try? UploadFailureStore.shared?.removed(identifier.rawValue, domain: remoteName)
                progress.completedUnitCount = progress.totalUnitCount
                handler.value(nil)
            } catch {
                logger.error("deleteItem failed: \(error)")
                handler.value(Self.mapToFileProviderError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Error Mapping

    static func mapToFileProviderError(_ error: Error) -> Error {
        if error is CancellationError {
            return CocoaError(.userCancelled)
        }
        if error is RcloneJobLostError {
            return NSFileProviderError(.serverUnreachable)
        }
        guard let rcloneError = error as? RcloneError else { return error }
        switch rcloneError {
        case .requestFailed(status: 404, _):
            return NSFileProviderError(.noSuchItem)
        case .requestFailed(status: 403, _):
            return NSFileProviderError(.notAuthenticated)
        case .serverNotRunning:
            return NSFileProviderError(.serverUnreachable)
        case .requestFailed, .invalidResponse, .decodingError:
            return NSFileProviderError(.serverUnreachable)
        }
    }

    // MARK: - Static Helpers (Sendable-safe)

    static func fetchItemStatic(
        rclone: RcloneClient,
        identifier: NSFileProviderItemIdentifier,
        remoteName: String
    ) async throws -> FileProviderItem {
        let remotePath = extractPathStatic(from: identifier, remoteName: remoteName)
        let parentPath = (remotePath as NSString).deletingLastPathComponent
        let filename = (remotePath as NSString).lastPathComponent

        // One `operations/stat`, not a listing of the parent: the system
        // asks for items one at a time (metadata refreshes, every download,
        // upload and thumbnail), and listing a folder of thousands of
        // items for each one took seconds apiece. The name check keeps the
        // old exact-match rule on services that match names loosely.
        guard let file = try await rclone.item(fs: "\(remoteName):", remote: remotePath),
              file.name == filename else {
            throw NSFileProviderError(.noSuchItem)
        }

        let parentId = parentPath.isEmpty
            ? NSFileProviderItemIdentifier.rootContainer
            : NSFileProviderItemIdentifier("\(remoteName):\(parentPath)")

        return FileProviderItem(from: file, parentIdentifier: parentId, remoteName: remoteName)
    }

    /// Inverse of `FileProviderItem`'s identifier construction — see the
    /// contract documented on `FileProviderItem`. `.rootContainer` must be
    /// special-cased to `""` since its raw value
    /// (`NSFileProviderRootContainerItemIdentifier`) never carries the
    /// `"<remoteName>:"` prefix; without this, any path built from a
    /// root-relative parent identifier (e.g. creating a new top-level item)
    /// would be silently prefixed with that literal system string instead
    /// of resolving to the remote root.
    static func extractPathStatic(from identifier: NSFileProviderItemIdentifier, remoteName: String) -> String {
        if identifier == .rootContainer { return "" }
        let raw = identifier.rawValue
        let prefix = "\(remoteName):"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }

    /// Best-effort file size lookup for wiring real `Progress.totalUnitCount`
    /// values into upload paths. Falls back to `orDefault` (never `0`, so
    /// `Progress` still reports meaningful, non-degenerate completion) when
    /// the URL is `nil` or unreadable.
    private static func fileSizeOnDisk(_ url: URL?, orDefault: Int64) -> Int64 {
        guard let url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size > 0
        else { return orDefault }
        return size
    }

    /// Advances `progress` from a move or purge job's file counts without
    /// knowing the total up front: `totalUnitCount` is raised first so
    /// `completedUnitCount` never exceeds it, and neither count decreases.
    private static func reportJobProgress(_ stats: StatsResponse, on progress: Progress) {
        let done = Int64(stats.transfers + (stats.renames ?? 0) + stats.deletes)
        progress.totalUnitCount = max(progress.totalUnitCount, done + 1)
        progress.completedUnitCount = max(progress.completedUnitCount, done)
    }

    /// True on a move retry when an earlier attempt already finished moving
    /// `sourcePath` to `destinationPath`.
    private static func alreadyMoved(
        rclone: RcloneClient,
        remoteName: String,
        from sourcePath: String,
        to destinationPath: String
    ) async throws -> Bool {
        let fs = "\(remoteName):"
        guard try await rclone.item(fs: fs, remote: sourcePath) == nil else { return false }
        return try await rclone.item(fs: fs, remote: destinationPath) != nil
    }
}

// MARK: - Finder actions

extension FileProviderExtension: NSFileProviderCustomAction {
    func performAction(
        identifier actionIdentifier: NSFileProviderExtensionActionIdentifier,
        onItemsWithIdentifiers itemIdentifiers: [NSFileProviderItemIdentifier],
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        if ShareLinkAction.handles(actionIdentifier) {
            refreshPort()
            let rclone = self.rclone
            let remoteName = domain.identifier.rawValue
            let logger = self.logger
            let handler = SendableBox(value: completionHandler)
            let task = Task { @Sendable in
                do {
                    try await ShareLinkAction.perform(items: itemIdentifiers, remoteName: remoteName,
                                                      rclone: rclone, logger: logger)
                    progress.completedUnitCount = 1
                    handler.value(nil)
                } catch is CancellationError {
                    handler.value(CocoaError(.userCancelled))
                } catch {
                    logger.error("Copy Share Link failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
                    handler.value(error)
                }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        guard KeepDownloadedAction.handles(actionIdentifier) else {
            completionHandler(CocoaError(.featureUnsupported))
            return progress
        }
        // NSFileProviderDomain isn't Sendable; it is only read here.
        let domain = SendableBox(value: self.domain)
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let task = Task { @Sendable in
            do {
                try await KeepDownloadedAction.perform(actionIdentifier, items: itemIdentifiers,
                                                       domain: domain.value, logger: logger)
                progress.completedUnitCount = 1
                handler.value(nil)
            } catch is CancellationError {
                handler.value(CocoaError(.userCancelled))
            } catch {
                logger.error("Keep Downloaded action failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
                handler.value(error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }
}
