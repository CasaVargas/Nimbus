import Foundation
import RcloneKit

/// What a cloud is called on screen. rclone's own words ("Alias for an
/// existing remote") never reach the user: an alias shows the service that
/// actually stores its files.
enum CloudNaming {
    /// Follows `alias` remotes to the backend that stores the files
    /// ("Personal Drive" → alias of "gdrive:" → "drive"). Stops on a cycle or
    /// a target that isn't another remote (e.g. a local path).
    static func resolvedType(of remote: Remote, in remotes: [Remote]) -> String {
        var current = remote
        var seen: Set<String> = []
        while current.type == "alias", let target = current.config["remote"], !seen.contains(current.name) {
            seen.insert(current.name)
            let name = CloudSummaryBuilder.cloudName(of: target)
            guard let next = remotes.first(where: { $0.name == name }) else { break }
            current = next
        }
        return current.type
    }

    /// Display name for a (resolved) backend type.
    @MainActor
    static func providerName(forType type: String, directory: ProviderDirectory) -> String {
        type == "alias" ? "Shortcut to a folder" : directory.displayName(forType: type)
    }
}
