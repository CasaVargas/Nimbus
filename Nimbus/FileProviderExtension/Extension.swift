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
        logger.info("Extension initialized for domain \(domain.identifier.rawValue) on port \(port)")
    }

    func invalidate() {}

    // MARK: - Item Lookup

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
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
                handler.value(nil, error)
            }
        }
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        FileProviderEnumerator(
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
        let rclone = self.rclone
        let remoteName = domain.identifier.rawValue
        let logger = self.logger
        let handler = SendableBox(value: completionHandler)
        let remotePath = Self.extractPathStatic(from: itemIdentifier, remoteName: remoteName)

        Task { @Sendable in
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("app.casavargas.nimbus.fileprovider", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let filename = (remotePath as NSString).lastPathComponent
                let localURL = tempDir.appendingPathComponent(filename)

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
                handler.value(nil, nil, error)
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
                handler.value(nil, [], false, error)
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
                handler.value(nil, [], false, error)
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
                handler.value(error)
            }
        }
        return Progress()
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

    private static func readPort() -> Int {
        let defaults = UserDefaults(suiteName: "group.app.casavargas.nimbus")
        return defaults?.integer(forKey: "rclonePort") ?? 5572
    }
}
