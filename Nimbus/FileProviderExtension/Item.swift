import FileProvider
import RcloneKit
import UniformTypeIdentifiers

final class FileProviderItem: NSObject, NSFileProviderItem {
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

    init(from file: FileItem, parentIdentifier: NSFileProviderItemIdentifier, remoteName: String) {
        self.itemIdentifier = NSFileProviderItemIdentifier("\(remoteName):\(file.path)")
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
    }

    static func rootContainer(domain: NSFileProviderDomain) -> FileProviderItem {
        FileProviderItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            name: domain.displayName
        )
    }
}
