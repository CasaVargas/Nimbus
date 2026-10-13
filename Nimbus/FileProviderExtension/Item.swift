import FileProvider
import RcloneKit
import UniformTypeIdentifiers

/// Identifier contract: `NSFileProviderItemIdentifier.rawValue` is always
/// `"<remoteName>:<fullPathFromRemoteRoot>"` (root itself is `.rootContainer`,
/// never a synthesized `"remoteName:"` string). rclone's `operations/list`
/// (and `operations/stat`) return each entry's `Path` relative to the ROOT
/// of the `fs` argument — verified empirically against the RC API: listing
/// `fs:"gdrive:" remote:"Documents/Adobe"` yields Paths like
/// `"Documents/Adobe/<name>"`, container prefix included. `file.path` is
/// therefore already the full path from the remote root and MUST NOT be
/// re-qualified with the container path (doing so double-prefixes every
/// child and breaks enumeration below the first level). A comment in
/// `BrowserViewModel` claims container-relative Paths; its code works only
/// because it feeds `item.path` back to rclone unmodified.
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
    ///   - file: The raw rclone listing entry. `file.path` is already the
    ///     full path from the remote root (rclone Paths are fs-root-relative;
    ///     see the type doc comment).
    ///   - parentIdentifier: Identifier of the container that was listed —
    ///     `.rootContainer` for the remote root.
    ///   - remoteName: The rclone remote name (domain identifier).
    init(from file: FileItem, parentIdentifier: NSFileProviderItemIdentifier, remoteName: String) {
        let fullPath = file.path
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
            self.capabilities = [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting]
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

}
