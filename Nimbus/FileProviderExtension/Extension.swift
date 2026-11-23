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
        let mayAlreadyExist = options.contains(.mayAlreadyExist)
        let domainBox = SendableBox(value: domain)

        let progress = Progress(totalUnitCount: Self.fileSizeOnDisk(localURL, orDefault: 1))
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                let requestedPath = parentPath.isEmpty ? filename : "\(parentPath)/\(filename)"
                var newPath = requestedPath
                var shouldFetchContent = false

                if isFolder {
                    // Check before `withWriteRetry` so a first attempt that fails
                    // to reach the daemon can't skip the collision check.
                    let (targetPath, shouldCreate) = try await FileProviderRetry.withReadRetry(
                        rclone: rclone, logger: logger, operation: "createItem.check"
                    ) { () -> (String, Bool) in
                        if mayAlreadyExist {
                            guard let existing = try await rclone.item(fs: "\(remoteName):", remote: requestedPath) else {
                                return (requestedPath, true)
                            }
                            if existing.isDir, existing.name == filename {
                                return (requestedPath, false)
                            }
                            let first = CollisionName.firstNumber(for: filename, isFolder: true)
                            let resolved = try await Self.resolveDestination(
                                rclone: rclone, remoteName: remoteName,
                                source: nil, destination: requestedPath,
                                isFolder: true, startingAfter: first - 1
                            )
                            return (resolved.path, true)
                        }
                        let resolved = try await Self.resolveDestination(
                            rclone: rclone, remoteName: remoteName,
                            source: nil, destination: requestedPath, isFolder: true
                        )
                        return (resolved.path, true)
                    }
                    newPath = targetPath
                    if newPath != requestedPath {
                        logger.info("createItem folder collision resolved: \(requestedPath, privacy: .private) → \(newPath, privacy: .private)")
                    }
                    if shouldCreate {
                        // `createFolder` is idempotent, so retrying after our own
                        // mkdir is safe. It has no Immutable option, so a folder
                        // created during the check-to-mkdir race merges (accepted).
                        try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "createItem.mkdir") { _ in
                            try await rclone.createFolder(fs: "\(remoteName):", remote: targetPath)
                        }
                    }
                } else if let localURL {
                    // rclone can't read the system-staged `localURL` where
                    // it is, so `ContentTransfer` clones it into the app
                    // group container for the daemon to upload, or (the
                    // fallback) sends the bytes over HTTP. The destination
                    // filename is passed explicitly since `localURL` isn't
                    // guaranteed to be named `filename`.
                    do {
                        if mayAlreadyExist {
                            let existing = try await FileProviderRetry.withReadRetry(
                                rclone: rclone, logger: logger, operation: "createItem.check"
                            ) {
                                try await rclone.item(fs: "\(remoteName):", remote: requestedPath)
                            }
                            if let existing, existing.isDir || existing.name != filename {
                                newPath = try await Self.uploadUnderFreeName(
                                    rclone: rclone, remoteName: remoteName, localURL: localURL,
                                    requestedPath: requestedPath, skipRequested: true,
                                    progress: progress, logger: logger
                                )
                                if newPath != requestedPath {
                                    logger.info("createItem file collision resolved: \(requestedPath, privacy: .private) → \(newPath, privacy: .private)")
                                }
                            } else {
                                do {
                                    try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "createItem.upload") { _ in
                                        try await ContentTransfer.upload(
                                            rclone: rclone, from: localURL, remoteName: remoteName,
                                            directory: parentPath, filename: filename,
                                            progress: progress, logger: logger, immutable: true
                                        )
                                    }
                                } catch let error as RcloneError where error.isDestinationConflict {
                                    let conflictPath = try await Self.uploadConflictCopy(
                                        rclone: rclone, remoteName: remoteName, contents: localURL,
                                        directory: parentPath, filename: filename,
                                        progress: progress, logger: logger
                                    )
                                    await Self.notifyConflictCopy(
                                        path: conflictPath, remoteName: remoteName,
                                        domain: domainBox.value, logger: logger
                                    )
                                    shouldFetchContent = true
                                }
                            }
                        } else {
                            newPath = try await Self.uploadUnderFreeName(
                                rclone: rclone, remoteName: remoteName, localURL: localURL,
                                requestedPath: requestedPath, progress: progress, logger: logger
                            )
                            if newPath != requestedPath {
                                logger.info("createItem file collision resolved: \(requestedPath, privacy: .private) → \(newPath, privacy: .private)")
                            }
                        }
                    } catch {
                        await UploadFailureReporting.failed(
                            error, identifier: "\(remoteName):\(newPath)",
                            domain: domainBox.value, logger: logger
                        )
                        throw error
                    }
                    UploadFailureReporting.succeeded(
                        ["\(remoteName):\(requestedPath)", "\(remoteName):\(newPath)"],
                        remoteName: remoteName, logger: logger
                    )
                } else if mayAlreadyExist {
                    // Dataless re-import: match an existing server file, or return
                    // nil with no error so the system removes the stale placeholder.
                    let existing = try await FileProviderRetry.withReadRetry(
                        rclone: rclone, logger: logger, operation: "createItem.stat"
                    ) {
                        try await rclone.item(fs: "\(remoteName):", remote: requestedPath)
                    }
                    guard let existing, !existing.isDir, existing.name == filename else {
                        progress.completedUnitCount = progress.totalUnitCount
                        handler.value(nil, [], false, nil)
                        return
                    }
                    let item = FileProviderItem(
                        from: existing,
                        parentIdentifier: Self.parentIdentifier(for: requestedPath, remoteName: remoteName),
                        remoteName: remoteName
                    )
                    progress.completedUnitCount = progress.totalUnitCount
                    handler.value(item, [], false, nil)
                    return
                }

                let createdPath = newPath
                let item = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "createItem.stat") {
                    try await Self.fetchItemStatic(
                        rclone: rclone,
                        identifier: NSFileProviderItemIdentifier("\(remoteName):\(createdPath)"),
                        remoteName: remoteName
                    )
                }
                progress.completedUnitCount = progress.totalUnitCount
                handler.value(item, [], shouldFetchContent, nil)
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
        let mayAlreadyExist = options.contains(.mayAlreadyExist)
        let baseContentVersion = baseVersion.contentVersion
        let baseIsBeforeFirstSync = baseContentVersion == NSFileProviderItemVersion.beforeFirstSyncComponent
        let systemIdentifier = item.itemIdentifier.rawValue
        let domainBox = SendableBox(value: domain)

        let progress = Progress(totalUnitCount: hasContentsChange ? Self.fileSizeOnDisk(contentsURL, orDefault: 1) : 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                if mayAlreadyExist {
                    logger.info("modifyItem called with mayAlreadyExist for \(systemIdentifier, privacy: .private)")
                }
                var workingPath = currentPath
                var shouldFetchContent = false
                var editDecision: EditConflict.Decision = .upload
                var hasCheckedSource = false
                var sourceFileAtCurrentPath: FileItem?
                var contentsUploadedDuringMove = false

                if hasContentsChange, contentsURL != nil {
                    // rclone RC has no If-Match, so the lookup-to-upload race
                    // remains; this catches server edits that happened before
                    // the upload starts.
                    let serverFile = try await FileProviderRetry.withReadRetry(
                        rclone: rclone, logger: logger, operation: "modifyItem.versionCheck"
                    ) {
                        try await rclone.item(fs: "\(remoteName):", remote: currentPath)
                    }
                    hasCheckedSource = true
                    sourceFileAtCurrentPath = serverFile
                    let serverContentVersion = serverFile.map {
                        ItemVersionBytes.content(
                            seconds: $0.modTime?.timeIntervalSince1970,
                            size: $0.size,
                            isDir: $0.isDir
                        )
                    }
                    editDecision = EditConflict.decide(
                        baseContentVersion: baseContentVersion,
                        baseIsBeforeFirstSync: baseIsBeforeFirstSync,
                        serverContentVersion: serverContentVersion
                    )
                }

                if isRenameOrMove {
                    let requestedPath = newParentPath.isEmpty ? newFilename : "\(newParentPath)/\(newFilename)"
                    if requestedPath != currentPath {
                        let onMoveProgress: @Sendable (StatsResponse) -> Void = { stats in
                            AppWaker.ping()
                            if !hasContentsChange {
                                Self.reportJobProgress(stats, on: progress)
                            }
                        }
                        let destinationPath: String
                        if isDirectory {
                            let pendingPath = PendingFolderMoveStore.shared?.pendingDestination(
                                from: currentPath, requested: requestedPath, domain: remoteName
                            )
                            let resumingFolderMove = pendingPath != nil
                            if let pendingPath {
                                destinationPath = pendingPath
                            } else {
                                let resolved = try await FileProviderRetry.withReadRetry(
                                    rclone: rclone, logger: logger, operation: "modifyItem.check"
                                ) {
                                    try await Self.resolveDestination(
                                        rclone: rclone, remoteName: remoteName,
                                        source: currentPath, destination: requestedPath, isFolder: true
                                    )
                                }
                                destinationPath = resolved.path
                                if destinationPath != requestedPath {
                                    logger.info("modifyItem folder collision resolved: \(requestedPath, privacy: .private) → \(destinationPath, privacy: .private)")
                                }
                                if destinationPath != currentPath {
                                    // Persist before starting so a cancelled folder move
                                    // resumes into our own partial destination on the next
                                    // attempt instead of colliding.
                                    try? PendingFolderMoveStore.shared?.begin(
                                        from: currentPath, requested: requestedPath,
                                        resolved: destinationPath, domain: remoteName
                                    )
                                }
                            }
                            let targetPath = destinationPath
                            if targetPath != currentPath {
                                do {
                                    try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.move") { isRetry in
                                        // A resumed folder move may find that the job of
                                        // an interrupted call (a killed process doesn't
                                        // stop it) already finished.
                                        if isRetry || resumingFolderMove, try await Self.alreadyMoved(
                                            rclone: rclone, remoteName: remoteName,
                                            from: currentPath, to: targetPath, isDirectory: true
                                        ) {
                                            return
                                        }
                                        // rclone has no "rename a directory" RC verb —
                                        // `operations/movefile` only moves individual
                                        // files — so directory renames/moves go
                                        // through `sync/move` treating both the
                                        // current and destination paths as directory
                                        // roots (the `rclone move <src> <dst>` CLI
                                        // command's RC equivalent).
                                        try await rclone.moveDirectoryAndWait(
                                            srcFs: "\(remoteName):\(currentPath)",
                                            dstFs: "\(remoteName):\(targetPath)",
                                            immutable: true,
                                            onProgress: onMoveProgress
                                        )
                                    }
                                } catch let error as RcloneError where error.isDestinationConflict {
                                    try? PendingFolderMoveStore.shared?.finish(
                                        from: currentPath, requested: requestedPath, domain: remoteName
                                    )
                                    throw await Self.collisionError(rclone: rclone, remoteName: remoteName, path: targetPath)
                                } catch RcloneError.requestFailed(status: 404, let message) {
                                    try? PendingFolderMoveStore.shared?.finish(
                                        from: currentPath, requested: requestedPath, domain: remoteName
                                    )
                                    throw RcloneError.requestFailed(status: 404, message: message)
                                }
                                try? PendingFolderMoveStore.shared?.finish(
                                    from: currentPath, requested: requestedPath, domain: remoteName
                                )
                            }
                        } else {
                            // An earlier call may have moved the file already (and
                            // failed at the upload or final stat), or the server may
                            // have deleted it. Moves keep size and modtime, so an
                            // equal content version at `requestedPath` identifies our
                            // own move; otherwise a local edit is recreated under a
                            // free name rather than lost.
                            let checkedSource = hasCheckedSource
                            let cachedSource = sourceFileAtCurrentPath
                            let (sourceFile, existingAtRequested) = try await FileProviderRetry.withReadRetry(
                                rclone: rclone, logger: logger, operation: "modifyItem.check"
                            ) { () -> (FileItem?, FileItem?) in
                                let src = if checkedSource {
                                    cachedSource
                                } else {
                                    try await rclone.item(fs: "\(remoteName):", remote: currentPath)
                                }
                                if src != nil {
                                    return (src, nil)
                                }
                                let dst = try await rclone.item(fs: "\(remoteName):", remote: requestedPath)
                                return (nil, dst)
                            }

                            if sourceFile == nil {
                                let existingFileVersion: Data? = if let existingAtRequested, !existingAtRequested.isDir {
                                    ItemVersionBytes.content(
                                        seconds: existingAtRequested.modTime?.timeIntervalSince1970,
                                        size: existingAtRequested.size,
                                        isDir: false
                                    )
                                } else {
                                    nil
                                }
                                if let existingFileVersion, existingFileVersion == baseContentVersion {
                                    destinationPath = requestedPath
                                    if hasContentsChange, contentsURL != nil {
                                        editDecision = EditConflict.decide(
                                            baseContentVersion: baseContentVersion,
                                            baseIsBeforeFirstSync: baseIsBeforeFirstSync,
                                            serverContentVersion: existingFileVersion
                                        )
                                    }
                                } else if hasContentsChange, let contentsURL {
                                    do {
                                        // A file at the new name may be this same
                                        // recreate from an earlier call whose reply was
                                        // lost: Immutable accepts it when identical.
                                        var uploadedAtRequested = false
                                        if let existingAtRequested, !existingAtRequested.isDir,
                                           existingAtRequested.name == newFilename {
                                            do {
                                                try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.upload") { _ in
                                                    try await ContentTransfer.upload(
                                                        rclone: rclone, from: contentsURL, remoteName: remoteName,
                                                        directory: (requestedPath as NSString).deletingLastPathComponent,
                                                        filename: newFilename,
                                                        progress: progress, logger: logger, immutable: true
                                                    )
                                                }
                                                uploadedAtRequested = true
                                            } catch let error as RcloneError where error.isDestinationConflict {
                                                // Someone else's file: use a free name below.
                                            }
                                        }
                                        if uploadedAtRequested {
                                            destinationPath = requestedPath
                                        } else {
                                            destinationPath = try await Self.uploadUnderFreeName(
                                                rclone: rclone, remoteName: remoteName, localURL: contentsURL,
                                                requestedPath: requestedPath, progress: progress, logger: logger
                                            )
                                        }
                                    } catch {
                                        await UploadFailureReporting.failed(
                                            error, identifier: systemIdentifier,
                                            domain: domainBox.value, logger: logger
                                        )
                                        throw error
                                    }
                                    if destinationPath != requestedPath {
                                        logger.info("modifyItem file collision resolved: \(requestedPath, privacy: .private) → \(destinationPath, privacy: .private)")
                                    }
                                    contentsUploadedDuringMove = true
                                } else {
                                    throw NSFileProviderError(.noSuchItem)
                                }
                            } else {
                                var startingAfter: Int?
                                let firstNumber = CollisionName.firstNumber(for: newFilename, isFolder: false)
                                var movedPath: String?
                                for _ in 0..<3 {
                                    let currentStartingAfter = startingAfter
                                    let resolved = try await FileProviderRetry.withReadRetry(
                                        rclone: rclone, logger: logger, operation: "modifyItem.check"
                                    ) {
                                        try await Self.resolveDestination(
                                            rclone: rclone, remoteName: remoteName,
                                            source: currentPath, destination: requestedPath,
                                            isFolder: false, startingAfter: currentStartingAfter
                                        )
                                    }
                                    let candidatePath = resolved.path
                                    if candidatePath == currentPath {
                                        movedPath = candidatePath
                                        break
                                    }
                                    do {
                                        try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.move") { isRetry in
                                            if isRetry, try await Self.alreadyMoved(
                                                rclone: rclone, remoteName: remoteName,
                                                from: currentPath, to: candidatePath, isDirectory: false
                                            ) {
                                                return
                                            }
                                            try await rclone.moveFileAndWait(
                                                srcFs: "\(remoteName):", srcRemote: currentPath,
                                                dstFs: "\(remoteName):", dstRemote: candidatePath,
                                                immutable: true,
                                                onProgress: onMoveProgress
                                            )
                                        }
                                        movedPath = candidatePath
                                        break
                                    } catch let error as RcloneError where error.isDestinationConflict {
                                        startingAfter = resolved.number ?? (firstNumber - 1)
                                    }
                                }
                                guard let resolvedMove = movedPath else {
                                    throw await Self.collisionError(rclone: rclone, remoteName: remoteName, path: requestedPath)
                                }
                                if resolvedMove != requestedPath {
                                    logger.info("modifyItem file collision resolved: \(requestedPath, privacy: .private) → \(resolvedMove, privacy: .private)")
                                }
                                destinationPath = resolvedMove
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
                    if !contentsUploadedDuringMove {
                        let uploadDir = (workingPath as NSString).deletingLastPathComponent
                        let uploadFilename = (workingPath as NSString).lastPathComponent
                        do {
                            var keepBoth = false
                            switch editDecision {
                            case .upload:
                                try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.upload") { _ in
                                    try await ContentTransfer.upload(
                                        rclone: rclone, from: contentsURL, remoteName: remoteName,
                                        directory: uploadDir, filename: uploadFilename,
                                        progress: progress, logger: logger
                                    )
                                }
                            case .uploadUnlessDifferent, .keepBoth:
                                // A version mismatch still tries the original first:
                                // rclone skips an identical file (our own earlier
                                // upload whose reply was lost) and refuses a
                                // different one, which is the real conflict.
                                do {
                                    try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "modifyItem.upload") { _ in
                                        try await ContentTransfer.upload(
                                            rclone: rclone, from: contentsURL, remoteName: remoteName,
                                            directory: uploadDir, filename: uploadFilename,
                                            progress: progress, logger: logger, immutable: true
                                        )
                                    }
                                } catch let error as RcloneError where error.isDestinationConflict {
                                    keepBoth = true
                                }
                            }

                            if keepBoth {
                                let conflictPath = try await Self.uploadConflictCopy(
                                    rclone: rclone, remoteName: remoteName, contents: contentsURL,
                                    directory: uploadDir, filename: uploadFilename,
                                    progress: progress, logger: logger
                                )
                                await Self.notifyConflictCopy(
                                    path: conflictPath, remoteName: remoteName,
                                    domain: domainBox.value, logger: logger
                                )
                                shouldFetchContent = true
                            }
                        } catch {
                            // Under the identifier the system knows: after a
                            // rename in this same call, the new one isn't its yet.
                            await UploadFailureReporting.failed(error, identifier: systemIdentifier,
                                                                domain: domainBox.value, logger: logger)
                            throw error
                        }
                    }
                    UploadFailureReporting.succeeded([systemIdentifier, "\(remoteName):\(workingPath)"],
                                                     remoteName: remoteName, logger: logger)
                }

                let newIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(workingPath)")
                let resultItem = try await FileProviderRetry.withReadRetry(rclone: rclone, logger: logger, operation: "modifyItem.stat") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: newIdentifier, remoteName: remoteName)
                }
                // The system takes a folder returned under a new identifier as already
                // listed and empty; hand it the listing through the working set.
                let movedFolderRelisted = if isDirectory, isRenameOrMove, workingPath != currentPath {
                    await Self.relistMovedFolder(rclone: rclone, remoteName: remoteName,
                                                 from: currentPath, to: workingPath, logger: logger)
                } else {
                    false
                }
                progress.completedUnitCount = progress.totalUnitCount
                handler.value(resultItem, [], shouldFetchContent, nil)
                if movedFolderRelisted {
                    SyncSnapshotStore.markNewlyListed(remoteName: remoteName, containerIdentifier: newIdentifier)
                    await Self.signalWorkingSet(domain: domainBox.value, logger: logger)
                }
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
                                AppWaker.ping()
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
        case .requestFailed(status: 409, _):
            return NSFileProviderError(.filenameCollision)
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

        return FileProviderItem(
            from: file,
            parentIdentifier: parentIdentifier(for: remotePath, remoteName: remoteName),
            remoteName: remoteName
        )
    }

    private static func parentIdentifier(for path: String, remoteName: String) -> NSFileProviderItemIdentifier {
        let parentPath = (path as NSString).deletingLastPathComponent
        return parentPath.isEmpty
            ? .rootContainer
            : NSFileProviderItemIdentifier("\(remoteName):\(parentPath)")
    }

    private static func collisionError(for existing: FileItem, path: String, remoteName: String) -> NSError {
        let item = FileProviderItem(
            from: existing,
            parentIdentifier: parentIdentifier(for: path, remoteName: remoteName),
            remoteName: remoteName
        )
        return NSError.fileProviderErrorForCollision(with: item)
    }

    private static func collisionError(rclone: RcloneClient, remoteName: String, path: String) async -> Error {
        if let existing = try? await rclone.item(fs: "\(remoteName):", remote: path) {
            return collisionError(for: existing, path: path, remoteName: remoteName)
        }
        return NSFileProviderError(.filenameCollision)
    }

    private static let maxCollisionCandidates = 19

    /// Returns `destination` when it is free, or the first free Finder-style
    /// alternative (`"report 2.pdf"`, `"Folder 2"`, …) across up to 19
    /// candidate numbers starting from `CollisionName.firstNumber`.
    ///
    /// With `startingAfter == nil` it checks `destination` itself first and
    /// returns `(destination, nil)` when free. With `startingAfter` set (a 409
    /// race round) it skips `destination` and tries candidates from
    /// `max(firstNumber, startingAfter + 1)`. If every candidate is occupied,
    /// falls back to throwing the collision error for `destination`.
    private static func resolveDestination(
        rclone: RcloneClient,
        remoteName: String,
        source: String?,
        destination: String,
        isFolder: Bool,
        startingAfter: Int? = nil
    ) async throws -> (path: String, number: Int?) {
        let fs = "\(remoteName):"
        let parentPath = (destination as NSString).deletingLastPathComponent
        let requestedName = (destination as NSString).lastPathComponent
        var collidingAtRequested: FileItem?

        if startingAfter == nil {
            if let source, DestinationCheck.isCaseOnlyRename(from: source, to: destination) {
                // On case-insensitive backends `operations/stat` of the new case
                // returns the source itself, so list the parent and collide only on
                // an exact filename match (case-sensitive backends with both names).
                let entries = try await rclone.listFiles(fs: fs, remote: parentPath)
                collidingAtRequested = entries.first(where: { $0.name == requestedName })
            } else {
                collidingAtRequested = try await rclone.item(fs: fs, remote: destination)
            }
            if collidingAtRequested == nil {
                return (destination, nil)
            }
        }

        let firstNumber = CollisionName.firstNumber(for: requestedName, isFolder: isFolder)
        let start = if let startingAfter {
            max(firstNumber, startingAfter + 1)
        } else {
            firstNumber
        }

        for number in start ..< (start + maxCollisionCandidates) {
            let candidateName = CollisionName.candidate(for: requestedName, number: number, isFolder: isFolder)
            let candidatePath = parentPath.isEmpty ? candidateName : "\(parentPath)/\(candidateName)"
            if candidatePath == source {
                return (candidatePath, number)
            }
            if try await rclone.item(fs: fs, remote: candidatePath) == nil {
                return (candidatePath, number)
            }
        }

        if let collidingAtRequested {
            throw collisionError(for: collidingAtRequested, path: destination, remoteName: remoteName)
        }
        throw await collisionError(rclone: rclone, remoteName: remoteName, path: destination)
    }

    private static func uploadUnderFreeName(
        rclone: RcloneClient,
        remoteName: String,
        localURL: URL,
        requestedPath: String,
        skipRequested: Bool = false,
        progress: Progress,
        logger: Logger
    ) async throws -> String {
        let parentPath = (requestedPath as NSString).deletingLastPathComponent
        let filename = (requestedPath as NSString).lastPathComponent
        let firstNumber = CollisionName.firstNumber(for: filename, isFolder: false)
        var startingAfter: Int? = skipRequested ? (firstNumber - 1) : nil

        for _ in 0..<3 {
            let currentStartingAfter = startingAfter
            let resolved = try await FileProviderRetry.withReadRetry(
                rclone: rclone, logger: logger, operation: "createItem.check"
            ) {
                try await Self.resolveDestination(
                    rclone: rclone, remoteName: remoteName,
                    source: nil, destination: requestedPath,
                    isFolder: false, startingAfter: currentStartingAfter
                )
            }
            let chosenPath = resolved.path
            let uploadFilename = (chosenPath as NSString).lastPathComponent
            do {
                // `immutable: true` closes most of the check-to-upload
                // race and skips an identical retry of our own upload.
                try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "createItem.upload") { _ in
                    try await ContentTransfer.upload(
                        rclone: rclone, from: localURL, remoteName: remoteName,
                        directory: parentPath, filename: uploadFilename,
                        progress: progress, logger: logger, immutable: true
                    )
                }
                return chosenPath
            } catch let error as RcloneError where error.isDestinationConflict {
                startingAfter = resolved.number ?? (firstNumber - 1)
            }
        }
        throw await Self.collisionError(rclone: rclone, remoteName: remoteName, path: requestedPath)
    }

    private static let maxConflictCopyAttempts = 20

    private static func uploadConflictCopy(
        rclone: RcloneClient,
        remoteName: String,
        contents localURL: URL,
        directory: String,
        filename: String,
        progress: Progress,
        logger: Logger
    ) async throws -> String {
        let now = Date()
        for number in 1...maxConflictCopyAttempts {
            let conflictName = ConflictCopyName.make(for: filename, date: now, number: number)
            do {
                // `immutable: true` makes retries safe: an earlier attempt that
                // already uploaded these bytes is treated as done.
                try await FileProviderRetry.withWriteRetry(rclone: rclone, logger: logger, operation: "conflictCopy.upload") { _ in
                    try await ContentTransfer.upload(
                        rclone: rclone, from: localURL, remoteName: remoteName,
                        directory: directory, filename: conflictName,
                        progress: progress, logger: logger, immutable: true
                    )
                }
                return directory.isEmpty ? conflictName : "\(directory)/\(conflictName)"
            } catch let error as RcloneError where error.isDestinationConflict {
                continue
            }
        }
        // A 409 here would map to `.filenameCollision` and make the system
        // rename the original item; 503 records an upload failure and retries.
        throw RcloneError.requestFailed(status: 503, message: "no free conflict-copy name")
    }

    private static func notifyConflictCopy(
        path: String,
        remoteName: String,
        domain: NSFileProviderDomain,
        logger: Logger
    ) async {
        // WorkingSetEnumerator reports immediately only items in PinStore's
        // change log; signalling alone is a no-op during the hot-scan cooldown.
        try? PinStore.shared?.markChanged(["\(remoteName):\(path)"], domain: remoteName)
        await signalWorkingSet(domain: domain, logger: logger)
    }

    /// Lists a moved folder at its new path and hands it to the snapshot
    /// store (see `SyncSnapshotStore.folderMoved`). False if the listing
    /// failed; the move itself has succeeded either way.
    private static func relistMovedFolder(
        rclone: RcloneClient, remoteName: String, from oldPath: String, to newPath: String, logger: Logger
    ) async -> Bool {
        do {
            let listing = try await FileProviderRetry.withReadRetry(
                rclone: rclone, logger: logger, operation: "modifyItem.relist", maxAttempts: 2
            ) {
                try await rclone.listFiles(fs: "\(remoteName):", remote: newPath)
            }
            SyncSnapshotStore.folderMoved(
                remoteName: remoteName,
                from: NSFileProviderItemIdentifier("\(remoteName):\(oldPath)"),
                to: NSFileProviderItemIdentifier("\(remoteName):\(newPath)"),
                listing: listing
            )
            return true
        } catch {
            logger.info("modifyItem.relist failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func signalWorkingSet(domain: NSFileProviderDomain, logger: Logger) async {
        guard let manager = NSFileProviderManager(for: domain) else { return }
        do {
            try await manager.signalEnumerator(for: .workingSet)
        } catch {
            let ns = error as NSError
            logger.error("signalEnumerator(workingSet) failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
        }
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
        to destinationPath: String,
        isDirectory: Bool
    ) async throws -> Bool {
        let fs = "\(remoteName):"
        guard try await rclone.item(fs: fs, remote: sourcePath) == nil,
              let destination = try await rclone.item(fs: fs, remote: destinationPath) else {
            return false
        }
        return destination.isDir == isDirectory
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
