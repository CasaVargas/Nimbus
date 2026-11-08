import AppKit
import RcloneKit
import UniformTypeIdentifiers

/// The document icons Finder shows, resolved from the filename extension
/// through `NSWorkspace`. Cached per extension: a 10k-row listing asks for
/// the same handful of types over and over, and `NSWorkspace.icon(for:)`
/// is not free.
@MainActor
enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    static let folder: NSImage = NSWorkspace.shared.icon(for: .folder)

    static func image(for file: FileItem) -> NSImage {
        file.isDir ? folder : image(forFilename: file.name)
    }

    static func image(forFilename name: String) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        if let cached = cache[ext] { return cached }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }
}
