import AppKit
import FileProvider
import RcloneKit
import os

/// Finder's **Copy Share Link**: asks rclone for the item's public link
/// (`operations/publiclink`) and puts it on the clipboard. Finder only
/// offers it for a single item on a cloud whose service makes links
/// (`userInfo.canShare`, from `CloudCapabilities`).
enum ShareLinkAction {
    static let copy = "app.casavargas.nimbus.copyShareLink"

    static func handles(_ identifier: NSFileProviderExtensionActionIdentifier) -> Bool {
        identifier.rawValue == copy
    }

    static func perform(
        items: [NSFileProviderItemIdentifier],
        remoteName: String,
        rclone: RcloneClient,
        logger: Logger
    ) async throws {
        guard let item = items.first, item != .rootContainer else {
            throw CocoaError(.featureUnsupported)
        }
        let prefix = "\(remoteName):"
        let path = item.rawValue.hasPrefix(prefix) ? String(item.rawValue.dropFirst(prefix.count)) : item.rawValue
        guard let url = try await rclone.publicLink(fs: prefix, remote: path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                          userInfo: [NSLocalizedDescriptionKey: "The service didn't return a link."])
        }
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
        }
        ShareLinkSignal.announce(fileName: (path as NSString).lastPathComponent)
        logger.info("Copied a share link for one item")
    }
}
