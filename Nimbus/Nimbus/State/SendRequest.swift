import Foundation

/// Local files and folders on their way into a cloud: from the Services
/// menu today, from the share extension later. Shown by `SendToNimbusSheet`.
struct SendRequest: Identifiable, Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let url: URL
        let isDirectory: Bool
        /// nil for folders: their size isn't known without walking them.
        let size: Int64?

        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    let id: UUID
    let items: [Item]
    /// The share-extension inbox these came from, if any: removed when the
    /// send is cancelled (a sent one is left for its transfers to read and
    /// swept a day later).
    var inboxID: UUID?

    init(id: UUID = UUID(), items: [Item], inboxID: UUID? = nil) {
        self.id = id
        self.items = items
        self.inboxID = inboxID
    }

    /// Keeps file URLs that exist, once each, in the order given. nil when
    /// nothing is left to send.
    init?(urls: [URL], fileManager: FileManager = .default) {
        var seen = Set<String>()
        var items: [Item] = []
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), seen.insert(path).inserted else {
                continue
            }
            let size = isDirectory.boolValue
                ? nil
                : (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            items.append(Item(url: URL(fileURLWithPath: path), isDirectory: isDirectory.boolValue, size: size))
        }
        guard !items.isEmpty else { return nil }
        self.init(items: items)
    }

    /// "3 items · 14.2 MB". The size is left out when it's unknown: any
    /// folder, or nothing but folders.
    var summary: String {
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        guard items.allSatisfy({ $0.size != nil }) else { return count }
        let total = items.compactMap(\.size).reduce(0, +)
        return "\(count) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    /// "a.pdf, b.png, c.txt and 4 more".
    var nameList: String {
        let shown = items.prefix(3).map(\.name).joined(separator: ", ")
        let rest = items.count - 3
        return rest > 0 ? "\(shown) and \(rest) more" : shown
    }
}

/// What to do when a name is already taken in the destination folder.
enum SendClashPolicy: Sendable {
    case replace
    case keepBoth
}

/// The naming rules for a send, kept pure so they can be tested without a
/// cloud.
enum SendPlan {
    struct Step: Equatable, Sendable {
        let item: SendRequest.Item
        /// The name it gets in the destination folder.
        let destinationName: String
    }

    /// Names in `items` already present in the destination. Compared
    /// without case: most clouds treat "Report.pdf" and "report.pdf" as the
    /// same file, and asking once too often is the safe side.
    static func clashes(_ items: [SendRequest.Item], existing: Set<String>) -> [String] {
        let taken = Set(existing.map { $0.lowercased() })
        return items.map(\.name).filter { taken.contains($0.lowercased()) }
    }

    /// "report.pdf" → "report 2.pdf", then "report 3.pdf"…
    static func keepBothName(_ name: String, taken: Set<String>) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        guard lowered.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        // A leading-dot name (".env") is all extension to NSString; keep it whole.
        let (stem, suffix) = base.isEmpty ? (name, "") : (base, ext.isEmpty ? "" : ".\(ext)")
        var number = 2
        while lowered.contains("\(stem) \(number)\(suffix)".lowercased()) { number += 1 }
        return "\(stem) \(number)\(suffix)"
    }

    /// One step per item. Two sent items that share a name never land on
    /// each other, whatever the policy: the later one is renamed.
    static func steps(
        for items: [SendRequest.Item], existing: Set<String>, policy: SendClashPolicy
    ) -> [Step] {
        var taken = policy == .keepBoth ? existing : []
        return items.map { item in
            let name = keepBothName(item.name, taken: taken)
            taken.insert(name)
            return Step(item: item, destinationName: name)
        }
    }

    /// Joins a cloud folder and a name without doubling or leading slashes.
    static func destinationPath(folder: String, name: String) -> String {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? name : "\(trimmed)/\(name)"
    }
}
