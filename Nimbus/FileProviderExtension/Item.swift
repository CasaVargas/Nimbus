import FileProvider
import RcloneKit
import UniformTypeIdentifiers

/// Identifier contract: `NSFileProviderItemIdentifier.rawValue` is always
/// `"<remoteName>:<fullPathFromRemoteRoot>"` (root itself is `.rootContainer`,
/// never a synthesized `"remoteName:"` string). rclone's `operations/list`
/// returns each entry's `Path` *relative to the directory that was listed*,
/// not relative to the remote root — so callers must qualify `file.path`
/// with the full path of the container that was enumerated
/// (`containerPath`) before it's usable as a globally-unique identifier or
/// as the `remote` argument to any other rclone RC call. This mirrors the
/// `qualifiedRemotePath` convention `BrowserViewModel` uses on the app side.
final class FileProviderItem: NSObject, NSFileProviderItem, @unchecked Sendable {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    let documentSize: NSNumber?
    let contentModificationDate: Date?
    let creationDate: Date?
    let itemVersion: NSFileProviderItemVersion

    let capabilities: NSFileProviderItemCapabilities
    let contentPolicy: NSFileProviderContentPolicy = .downloadLazily

    /// Full path of `file` from the remote root (no remote-name prefix).
    /// Exposed so callers can reuse it for further rclone calls without
    /// re-deriving it from `itemIdentifier`.
    let fullPath: String

    /// - Parameters:
    ///   - file: The raw rclone listing entry. `file.path` is relative to
    ///     `containerPath`, per rclone's `operations/list` contract.
    ///   - containerPath: Full path (from the remote root, no remote-name
    ///     prefix) of the directory that was listed to produce `file`.
    ///     Empty string for the remote root.
    ///   - parentIdentifier: Identifier of the container that was listed —
    ///     `.rootContainer` when `containerPath` is empty.
    ///   - remoteName: The rclone remote name (domain identifier).
    init(from file: FileItem, containerPath: String, parentIdentifier: NSFileProviderItemIdentifier, remoteName: String) {
        let fullPath = Self.joinPath(containerPath, file.path)
        self.fullPath = fullPath
        self.itemIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(fullPath)")
        self.parentItemIdentifier = parentIdentifier
        self.filename = file.name
        self.contentModificationDate = file.modTime
        self.creationDate = file.modTime

        if file.isDir {
            self.contentType = .folder
            self.documentSize = nil
            self.capabilities = [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        } else {
            self.contentType = UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data
            self.documentSize = NSNumber(value: file.size)
            self.capabilities = [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsEvicting]
        }

        let versionData: Data
        if let modTime = file.modTime {
            versionData = withUnsafeBytes(of: modTime.timeIntervalSince1970) { Data($0) }
        } else {
            versionData = Data([0])
        }
        self.itemVersion = NSFileProviderItemVersion(contentVersion: versionData, metadataVersion: versionData)
    }

    private init(identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, name: String) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = name
        self.contentType = .folder
        self.documentSize = nil
        self.contentModificationDate = nil
        self.creationDate = nil
        self.capabilities = [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]
        self.itemVersion = NSFileProviderItemVersion(contentVersion: Data([0]), metadataVersion: Data([0]))
        self.fullPath = ""
    }

    static func rootContainer(domain: NSFileProviderDomain) -> FileProviderItem {
        FileProviderItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            name: domain.displayName
        )
    }

    /// Joins a container's full path with an entry path relative to it,
    /// matching the `qualifiedRemotePath` logic in `BrowserViewModel`.
    static func joinPath(_ containerPath: String, _ relativePath: String) -> String {
        containerPath.isEmpty ? relativePath : "\(containerPath)/\(relativePath)"
    }
}
