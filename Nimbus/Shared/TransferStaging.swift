import Foundation

/// Where the File Provider extension and the rclone daemon hand file
/// contents to each other: a folder in the app group container, the one
/// place the sandboxed extension and the app's daemon can both read and
/// write. Each transfer gets a folder of its own and removes it when done.
///
/// Going through here lets rclone open the file itself
/// (`RcloneClient.copyFileAndWait`) instead of the extension pushing every
/// byte through the daemon's HTTP API.
enum TransferStaging {
    static let folderName = "FileProviderTransfers"
    /// Folders untouched for this long belong to a transfer that never
    /// finished (the extension was killed mid-way) and are removed.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    static func root(in container: URL) -> URL {
        container.appendingPathComponent(folderName, isDirectory: true)
    }

    /// A new, empty folder for one transfer.
    static func makeFolder(in container: URL) throws -> URL {
        let folder = root(in: container).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The name a file is staged under. Only a plain extension survives from
    /// the user's file name: rclone can tell a file's type from it, while
    /// the rest could be too long once rclone adds its partial-download
    /// suffix, or hold characters rclone's local backend rewrites.
    static func stagedName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        let isPlain = !ext.isEmpty && ext.count <= 16
            && ext.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
        return isPlain ? "content.\(ext)" : "content"
    }

    /// Removes transfer folders in which nothing changed for `staleAfter`.
    /// A long transfer keeps its folder fresh: rclone keeps writing the file
    /// inside it.
    static func sweep(in container: URL, now: Date = Date()) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
        }
        let folders = (try? manager.contentsOfDirectory(at: root(in: container), includingPropertiesForKeys: keys)) ?? []
        for folder in folders {
            let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            guard let latest = ([folder] + contents).compactMap(modified).max() else { continue }
            if now.timeIntervalSince(latest) > staleAfter {
                try? manager.removeItem(at: folder)
            }
        }
    }
}
