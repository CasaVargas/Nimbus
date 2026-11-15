import Foundation

/// The hand-off between the share extension and the app. The extension
/// writes a folder per share into the app group container (a manifest, plus
/// copies of anything the app couldn't read where it is) and opens
/// `nimbus://send?inbox=<uuid>`; the app reads the manifest and shows the
/// Send to Nimbus sheet.
///
/// The URL carries an inbox id and nothing else on purpose: a web page can
/// open a `nimbus://` link, and it must not be able to name a file.
enum ShareInbox {
    static let folderName = "ShareInbox"
    static let manifestName = "manifest.json"
    static let urlScheme = "nimbus"
    /// Most the extension copies into one inbox. Past it the share is
    /// refused: Services or dragging don't need a copy.
    static let stagedByteLimit: Int64 = 2 * 1024 * 1024 * 1024
    /// Inboxes older than this are leftovers and are removed at launch.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    struct Item: Codable, Equatable, Sendable {
        /// Staged: a file name inside the inbox folder. Otherwise the
        /// absolute path of a file left where it is.
        let path: String
        let staged: Bool
    }

    struct Manifest: Codable, Equatable, Sendable {
        var version = 1
        var items: [Item]
    }

    enum Problem: Error, Equatable {
        case missing, unsupportedVersion, tooLarge
    }

    static func root(in container: URL) -> URL {
        container.appendingPathComponent(folderName, isDirectory: true)
    }

    static func folder(id: UUID, in container: URL) -> URL {
        root(in: container).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: Hand-off URL

    static func handoffURL(id: UUID) -> URL {
        URL(string: "\(urlScheme)://send?inbox=\(id.uuidString)")!
    }

    /// The inbox a hand-off URL names. Anything but exactly
    /// `nimbus://send?inbox=<uuid>` is refused.
    static func inboxID(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == urlScheme, parts.host == "send",
              parts.path.isEmpty || parts.path == "/",
              let items = parts.queryItems, items.count == 1, items[0].name == "inbox",
              let value = items[0].value else { return nil }
        return UUID(uuidString: value)
    }

    // MARK: Writing (extension)

    /// Files the unsandboxed app may not be able to read where they are:
    /// another app's container or a temporary folder. The extension copies
    /// those; everything else is passed by path.
    static func needsStaging(path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        return standardized.contains("/Library/Containers/")
            || standardized.contains("/Library/Group Containers/")
            || ["/private/var/", "/var/folders/", "/private/tmp/", "/tmp/"].contains { standardized.hasPrefix($0) }
    }

    /// A file name not yet used in the inbox: "Image.png", "Image 2.png"…
    static func uniqueName(_ name: String, taken: Set<String>) -> String {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        let base = clean.isEmpty || clean == manifestName ? "Shared Item" : clean
        guard taken.contains(base) else { return base }
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        var number = 2
        while taken.contains(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)") { number += 1 }
        return ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
    }

    static func write(_ manifest: Manifest, id: UUID, in container: URL) throws {
        let directory = folder(id: id, in: container)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    // MARK: Reading (app)

    static func read(id: UUID, in container: URL) throws -> Manifest {
        let url = folder(id: id, in: container).appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { throw Problem.missing }
        guard manifest.version == 1 else { throw Problem.unsupportedVersion }
        return manifest
    }

    /// Where each item is. A staged item must be a plain file name: one
    /// that tries to climb out of its inbox is dropped.
    static func fileURLs(of manifest: Manifest, id: UUID, in container: URL) -> [URL] {
        let directory = folder(id: id, in: container)
        return manifest.items.compactMap { item in
            if item.staged {
                guard !item.path.contains("/"), item.path != "..", item.path != ".", item.path != manifestName,
                      !item.path.isEmpty else { return nil }
                return directory.appendingPathComponent(item.path)
            }
            return item.path.hasPrefix("/") ? URL(fileURLWithPath: item.path) : nil
        }
    }

    // MARK: Cleanup

    static func remove(id: UUID, in container: URL) {
        try? FileManager.default.removeItem(at: folder(id: id, in: container))
    }

    /// Removes inboxes last changed more than `staleAfter` ago.
    static func sweep(in container: URL, now: Date = Date()) {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(
            at: root(in: container), includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > staleAfter {
                try? manager.removeItem(at: entry)
            }
        }
    }
}
