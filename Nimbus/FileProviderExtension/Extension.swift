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
        let port = Self.readPort()
        self.rclone = RcloneClient(port: port)
        logger.error("Extension init: domain=\(domain.identifier.rawValue), port=\(port)")
    }

    /// Re-reads the port from app group UserDefaults — the main app may have
    /// restarted on a different port since this extension process was spawned.
    private func refreshPort() {
        let port = Self.readPort()
        let currentPort = rclone.port
        if port != currentPort {
            logger.info("Port changed: \(currentPort) → \(port)")
            rclone.updatePort(port)
        }
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

        Task { @Sendable in
            do {
                let item = try await Self.fetchItemStatic(rclone: rclone, identifier: identifier, remoteName: remoteName)
                handler.value(item, nil)
            } catch {
                logger.error("item(for:) failed: \(error)")
                handler.value(nil, Self.mapToFileProviderError(error))
            }
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        refreshPort()
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

        Task { @Sendable in
            do {
                // NSTemporaryDirectory() resolves inside the sandbox container.
                // rclone (unsandboxed) can write here, and we can read it.
                let downloadDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("FileProviderDownloads", isDirectory: true)
                try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

                let filename = (remotePath as NSString).lastPathComponent
                let localURL = downloadDir.appendingPathComponent("\(UUID().uuidString)_\(filename)")

                // Use copyfile — rclone writes to our sandbox tmp path
                try await rclone.copyFile(
                    srcFs: "\(remoteName):",
                    srcRemote: remotePath,
                    dstFs: "/",
                    dstRemote: localURL.path
                )

                let item = try await Self.fetchItemStatic(rclone: rclone, identifier: itemIdentifier, remoteName: remoteName)
                handler.value(localURL, item, nil)
            } catch {
                logger.error("fetchContents failed: \(error)")
                handler.value(nil, nil, Self.mapToFileProviderError(error))
            }
        }
        return Progress()
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
        let isFolder = itemTemplate.contentType == .folder
        let localURL = url

        Task { @Sendable in
            do {
                let newPath = parentPath.isEmpty ? filename : "\(parentPath)/\(filename)"

                if isFolder {
                    try await rclone.mkdir(fs: "\(remoteName):", remote: newPath)
                } else if let localURL {
                    // rclone can read from our sandbox path since it's unsandboxed
                    try await rclone.copyFile(
                        srcFs: "/",
                        srcRemote: localURL.path,
                        dstFs: "\(remoteName):",
                        dstRemote: newPath
                    )
                }

                let item = try await Self.fetchItemStatic(
                    rclone: rclone,
                    identifier: NSFileProviderItemIdentifier("\(remoteName):\(newPath)"),
                    remoteName: remoteName
                )
                handler.value(item, [], false, nil)
            } catch {
                logger.error("createItem failed: \(error)")
                handler.value(nil, [], false, Self.mapToFileProviderError(error))
            }
        }
        return Progress()
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
        let hasContentsChange = changedFields.contains(.contents)
        let contentsURL = newContents

        Task { @Sendable in
            do {
                if hasContentsChange, let url = contentsURL {
                    try await rclone.copyFile(
                        srcFs: "/",
                        srcRemote: url.path,
                        dstFs: "\(remoteName):",
                        dstRemote: currentPath
                    )
                }

                let resultItem = try await Self.fetchItemStatic(
                    rclone: rclone,
                    identifier: NSFileProviderItemIdentifier("\(remoteName):\(currentPath)"),
                    remoteName: remoteName
                )
                handler.value(resultItem, [], false, nil)
            } catch {
                logger.error("modifyItem failed: \(error)")
                handler.value(nil, [], false, Self.mapToFileProviderError(error))
            }
        }
        return Progress()
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

        Task { @Sendable in
            do {
                try await rclone.deleteFile(fs: "\(remoteName):", remote: remotePath)
                handler.value(nil)
            } catch {
                logger.error("deleteItem failed: \(error)")
                handler.value(Self.mapToFileProviderError(error))
            }
        }
        return Progress()
    }

    // MARK: - Error Mapping

    private static func mapToFileProviderError(_ error: Error) -> Error {
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

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("app.casavargas.nimbus.FileProvider", isDirectory: true)
    }

    private static func cleanupTempDirectory() {
        let tempDir = tempDirectory()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Static Helpers (Sendable-safe)

    private static func fetchItemStatic(
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

    private static func extractPathStatic(from identifier: NSFileProviderItemIdentifier, remoteName: String) -> String {
        let raw = identifier.rawValue
        let prefix = "\(remoteName):"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }

    private static let appGroupID = "group.app.casavargas.nimbus"

    private static func readPort() -> Int {
        let logger = Logger(subsystem: "app.casavargas.nimbus.FileProvider", category: "extension")

        // Try UserDefaults first
        if let defaults = UserDefaults(suiteName: appGroupID),
           case let port = defaults.integer(forKey: "rclonePort"), port > 0 {
            logger.debug("Read port \(port) from UserDefaults")
            return port
        }

        // Try group container
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            if let port = Self.readPortFromJSON(containerURL.appendingPathComponent("shared-state.json")) {
                logger.debug("Read port \(port) from group container")
                return port
            }
        }

        // Try extension's own Application Support (main app writes here since it's unsandboxed)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let appSupport {
            if let port = Self.readPortFromJSON(appSupport.appendingPathComponent("shared-state.json")) {
                logger.debug("Read port \(port) from Application Support")
                return port
            }
        }

        logger.warning("App group port not found, using default 5572")
        return 5572
    }

    private static func readPortFromJSON(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["rclonePort"] as? Int, port > 0 else { return nil }
        return port
    }
}
