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

    /// Pinned with Keep Downloaded (directly, not via a folder).
    let isPinned: Bool
    /// Kept downloaded because a folder above it is pinned.
    let isKeptByFolder: Bool
    private let isRoot: Bool

    /// Root downloads lazily; a pinned item downloads now and stays; every
    /// other item inherits from its parent, so pinning a folder keeps
    /// everything inside it.
    var contentPolicy: NSFileProviderContentPolicy {
        switch PinPolicy.policy(isRoot: isRoot, isPinned: isPinned) {
        case .downloadLazily: .downloadLazily
        case .keepDownloaded: .downloadEagerlyAndKeepDownloaded
        case .inherited: .inherited
        }
    }

    /// 0 = not kept, 1 = pinned, 2 = kept because a folder above is pinned.
    var keepState: Int { Self.keepState(pinned: isPinned, keptByFolder: isKeptByFolder) }

    static func keepState(pinned: Bool, keptByFolder: Bool) -> Int {
        pinned ? 1 : (keptByFolder ? 2 : 0)
    }

    /// Read by the Finder actions' activation rules (extension Info.plist).
    var userInfo: [AnyHashable: Any]? {
        ["pinned": isPinned, "keptByFolder": isKeptByFolder]
    }

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
        let identifier = NSFileProviderItemIdentifier("\(remoteName):\(fullPath)")
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        let pins = PinStore.shared?.pins(domain: remoteName) ?? []
        let pinned = pins.contains(identifier.rawValue)
        let keptByFolder = PinPolicy.keptByAncestor(identifier.rawValue, pins: pins, rootKey: PinPolicy.rootKey)
        self.isPinned = pinned
        self.isKeptByFolder = keptByFolder
        self.isRoot = false
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
        // The pin state is metadata: folding it into the metadata version
        // tells the system the item changed (re-read its content policy)
        // while the unchanged content version means nothing re-downloads.
        var metadataVersion = versionData
        metadataVersion.append(UInt8(Self.keepState(pinned: pinned, keptByFolder: keptByFolder)))
        self.itemVersion = NSFileProviderItemVersion(contentVersion: versionData, metadataVersion: metadataVersion)
    }

    private init(identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, name: String,
                 remoteName: String) {
        self.itemIdentifier = identifier
        self.isPinned = PinStore.shared?.isPinned(identifier.rawValue, domain: remoteName) ?? false
        self.isKeptByFolder = false
        self.isRoot = true
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
            name: domain.displayName,
            remoteName: domain.identifier.rawValue
        )
    }

}
