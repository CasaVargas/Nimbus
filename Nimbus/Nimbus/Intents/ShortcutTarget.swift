import FileProvider
import Foundation

/// A file or folder handed to a Shortcuts action, as the cloud item it is:
/// the remote (File Provider domain) and its path from the cloud's top.
struct ShortcutTarget: Equatable, Sendable {
    let remote: String
    /// "" for the cloud's top folder.
    let path: String

    var identifier: String { "\(remote):\(path)" }
    var isTopFolder: Bool { path.isEmpty }

    /// Item identifiers are `"<remote>:<path>"`; the top folder is the
    /// system's root container. Nil for anything else.
    static func from(itemIdentifier: String, domain: String) -> ShortcutTarget? {
        guard !domain.isEmpty else { return nil }
        if itemIdentifier == NSFileProviderItemIdentifier.rootContainer.rawValue {
            return ShortcutTarget(remote: domain, path: "")
        }
        let prefix = "\(domain):"
        guard itemIdentifier.hasPrefix(prefix) else { return nil }
        return ShortcutTarget(remote: domain, path: String(itemIdentifier.dropFirst(prefix.count)))
    }

    /// Asks the File Provider which Nimbus item a Finder URL is.
    static func resolve(_ url: URL) async throws -> ShortcutTarget {
        let name = url.lastPathComponent
        let ids: (NSFileProviderItemIdentifier, NSFileProviderDomainIdentifier)
        do {
            ids = try await withCheckedThrowingContinuation { continuation in
                NSFileProviderManager.getIdentifierForUserVisibleFile(at: url) { item, domain, error in
                    if let item, let domain {
                        continuation.resume(returning: (item, domain))
                    } else {
                        continuation.resume(throwing: error ?? ShortcutError.notInCloud(name: name))
                    }
                }
            }
        } catch {
            throw ShortcutError.notInCloud(name: name)
        }
        guard let target = from(itemIdentifier: ids.0.rawValue, domain: ids.1.rawValue) else {
            throw ShortcutError.notInCloud(name: name)
        }
        return target
    }
}
