import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {

    let identifier: NSFileProviderItemIdentifier
    let parentIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let isFolder: Bool
    let fileSize: Int64
    let contentModificationDate: Date?
    let creationDate: Date?

    private let _version: NSFileProviderItemVersion

    init(
        identifier: NSFileProviderItemIdentifier,
        parentIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        isFolder: Bool,
        fileSize: Int64 = 0,
        contentModificationDate: Date? = nil,
        creationDate: Date? = nil
    ) {
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
        self.filename = filename
        self.isFolder = isFolder
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate

        // Version based on modification date or a default
        let versionData = "\(contentModificationDate?.timeIntervalSince1970 ?? 0)".data(using: .utf8) ?? Data()
        self._version = NSFileProviderItemVersion(contentVersion: versionData, metadataVersion: versionData)

        super.init()
    }

    // MARK: - NSFileProviderItem Protocol

    var itemIdentifier: NSFileProviderItemIdentifier { identifier }

    var parentItemIdentifier: NSFileProviderItemIdentifier { parentIdentifier }

    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsEvicting]
    }

    var contentPolicy: NSFileProviderContentPolicy {
        .downloadLazily
    }

    var itemVersion: NSFileProviderItemVersion { _version }

    var contentType: UTType {
        if isFolder {
            return .folder
        }
        return UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
    }

    var documentSize: NSNumber? {
        isFolder ? nil : NSNumber(value: fileSize)
    }

    // MARK: - Factory Methods

    static func rootContainer(domain: NSFileProviderDomain) -> FileProviderItem {
        FileProviderItem(
            identifier: .rootContainer,
            parentIdentifier: .rootContainer,
            filename: domain.displayName,
            isFolder: true
        )
    }

    /// Create from rclone `operations/list` JSON entry
    static func from(rcloneEntry: [String: Any], parentIdentifier: NSFileProviderItemIdentifier, remoteName: String) -> FileProviderItem? {
        guard let path = rcloneEntry["Path"] as? String else { return nil }
        let isDir = rcloneEntry["IsDir"] as? Bool ?? false
        let size = rcloneEntry["Size"] as? Int64 ?? 0
        let modTimeStr = rcloneEntry["ModTime"] as? String

        let modDate: Date? = {
            guard let str = modTimeStr else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: str)
        }()

        // Identifier encodes the full remote path: "remoteName:path/to/file"
        let fullPath = "\(remoteName):\(path)"
        let identifier = NSFileProviderItemIdentifier(fullPath)

        return FileProviderItem(
            identifier: identifier,
            parentIdentifier: parentIdentifier,
            filename: (path as NSString).lastPathComponent,
            isFolder: isDir,
            fileSize: size,
            contentModificationDate: modDate
        )
    }
}
