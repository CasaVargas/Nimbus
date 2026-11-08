import FileProvider
import RcloneKit
import os
import UniformTypeIdentifiers

private struct SendableBox<T>: @unchecked Sendable {
    let value: T
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    let rclone: RcloneClient
    private let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "extension")

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let port = FileProviderRetry.readPort()
        self.rclone = RcloneClient(port: port)
        logger.error("Extension init: domain=\(domain.identifier.rawValue), port=\(port)")
    }

    /// Re-reads the port from app group UserDefaults — the main app may have
    /// restarted on a different port since this extension process was spawned.
    private func refreshPort() {
        FileProviderRetry.refreshPort(on: rclone, logger: logger)
    }

    func invalidate() {
        Self.cleanupTempDirectory()
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
                let item = try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "item(for:)") {
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
            return WorkingSetEnumerator(domain: domain) { identifier in
                try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "workingSet.item") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: identifier, remoteName: remoteName)
                }
            }
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

        let progress = Progress(totalUnitCount: 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()

                // Fetch metadata first so we know the transfer size up front
                // (for progress) and can hand Finder the current item
                // alongside the bytes without a second round trip.
                let item = try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "fetchContents.stat") {
                    try await Self.fetchItemStatic(rclone: rclone, identifier: itemIdentifier, remoteName: remoteName)
                }
                if let size = item.documentSize?.int64Value, size > 0 {
                    progress.totalUnitCount = size
                }

                // `NSTemporaryDirectory()` resolves inside the extension's own
                // sandbox container. Unlike the old `operations/copyfile`
                // approach (which required the unsandboxed rclone process to
                // write into our sandbox), `downloadFile` streams bytes over
                // HTTP via `operations/cat` and this process writes them —
                // rclone never needs filesystem access to our container.
                let downloadDir = Self.tempDirectory().appendingPathComponent("Downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

                let filename = (remotePath as NSString).lastPathComponent
                let localURL = downloadDir.appendingPathComponent("\(UUID().uuidString)_\(filename)")

                try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "fetchContents.download") {
                    try await rclone.downloadFile(fs: "\(remoteName):", remote: remotePath, to: localURL)
                }

                progress.completedUnitCount = progress.totalUnitCount
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
        let filename = itemTemplate.filename
        let isFolder = itemTemplate.contentType?.conforms(to: .directory) ?? false
        let localURL = url

        let progress = Progress(totalUnitCount: Self.fileSizeOnDisk(localURL, orDefault: 1))
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                let newPath = parentPath.isEmpty ? filename : "\(parentPath)/\(filename)"

                if isFolder {
                    try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "createItem.mkdir") {
                        try await rclone.mkdir(fs: "\(remoteName):", remote: newPath)
                    }
                } else if let localURL {
                    // `uploadFile` streams bytes from our sandbox to rclone
                    // over HTTP (multipart), so — unlike the old
                    // `operations/copyfile` with `dstFs: "/"` — rclone never
                    // needs to read from our sandbox container directly. The
                    // destination filename is passed explicitly since the
                    // system-staged `localURL` isn't guaranteed to be named
                    // `filename`.
                    try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "createItem.upload") {
                        try await rclone.uploadFile(from: localURL, fs: "\(remoteName):", remote: parentPath, filename: filename)
                    }
                }

                let item = try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "createItem.stat") {
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
        let newFilename = item.filename
        let isDirectory = item.contentType?.conforms(to: .directory) ?? false
        let isRenameOrMove = changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier)
        let hasContentsChange = changedFields.contains(.contents)
        let contentsURL = newContents

        let progress = Progress(totalUnitCount: hasContentsChange ? Self.fileSizeOnDisk(contentsURL, orDefault: 1) : 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                var workingPath = currentPath

                if isRenameOrMove {
                    let destinationPath = newParentPath.isEmpty ? newFilename : "\(newParentPath)/\(newFilename)"
                    if destinationPath != currentPath {
                        try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "modifyItem.move") {
                            if isDirectory {
                                // rclone has no "rename a directory" RC verb —
                                // `operations/movefile` only moves individual
                                // files — so directory renames/moves go
                                // through `sync/move` treating both the
                                // current and destination paths as directory
                                // roots (the `rclone move <src> <dst>` CLI
                                // command's RC equivalent).
                                try await rclone.moveDirectory(
                                    srcFs: "\(remoteName):\(currentPath)",
                                    dstFs: "\(remoteName):\(destinationPath)"
                                )
                            } else {
                                try await rclone.moveFile(
                                    srcFs: "\(remoteName):", srcRemote: currentPath,
                                    dstFs: "\(remoteName):", dstRemote: destinationPath
                                )
                            }
                        }
                        workingPath = destinationPath
                        try? PinStore.shared?.moved(
                            from: "\(remoteName):\(currentPath)", to: "\(remoteName):\(destinationPath)",
                            domain: remoteName)
                    }
                }

                if hasContentsChange, let contentsURL {
                    let uploadDir = (workingPath as NSString).deletingLastPathComponent
                    let uploadFilename = (workingPath as NSString).lastPathComponent
                    try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "modifyItem.upload") {
                        try await rclone.uploadFile(from: contentsURL, fs: "\(remoteName):", remote: uploadDir, filename: uploadFilename)
                    }
                }

                let newIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(workingPath)")
                let resultItem = try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "modifyItem.stat") {
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

        let progress = Progress(totalUnitCount: 1)
        let task = Task { @Sendable in
            do {
                try Task.checkCancellation()
                try await FileProviderRetry.withRetry(rclone: rclone, logger: logger, operation: "deleteItem") {
                    // `deleteItem` only gets an identifier — a path — not the
                    // `NSFileProviderItem`, so directory-ness has to be
                    // determined authoritatively via `operations/stat`
                    // immediately before deleting rather than guessed from
                    // the identifier (which carries no type information) or
                    // a possibly-stale local cache. `operations/deletefile`
                    // fails on directories; those must go through
                    // `operations/purge` instead.
                    let stat = try await rclone.stat(fs: "\(remoteName):", remote: remotePath)
                    if stat.isDir {
                        try await rclone.purge(fs: "\(remoteName):", remote: remotePath)
                    } else {
                        try await rclone.deleteFile(fs: "\(remoteName):", remote: remotePath)
                    }
                }
                try? PinStore.shared?.removed(identifier.rawValue, domain: remoteName)
                progress.completedUnitCount = 1
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

    private static func mapToFileProviderError(_ error: Error) -> Error {
        if error is CancellationError {
            return CocoaError(.userCancelled)
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

    // MARK: - Temp Directory Management

    /// Single shared root for everything this extension writes to disk
    /// (currently just staged downloads). `invalidate()` removes exactly
    /// this directory, so every write path must nest under it — a prior
    /// version of `fetchContents` wrote to a differently-named directory
    /// than the one `invalidate()` cleaned up, leaking staged downloads.
    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("app.casavargas.nimbus.FileProvider", isDirectory: true)
    }

    private static func cleanupTempDirectory() {
        let tempDir = tempDirectory()
        try? FileManager.default.removeItem(at: tempDir)
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

        let files = try await rclone.listFiles(fs: "\(remoteName):", remote: parentPath)
        guard let file = files.first(where: { $0.name == filename }) else {
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
    private static func extractPathStatic(from identifier: NSFileProviderItemIdentifier, remoteName: String) -> String {
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
