import AppIntents
import AppKit
import Foundation
import UniformTypeIdentifiers

/// **Copy Share Link**: the service's public link for a file or folder in a
/// Nimbus cloud, on the clipboard and as the action's output. Uses the
/// service's default expiry (a week on S3, none elsewhere), like Finder's
/// action.
struct CopyShareLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Share Link"
    static let description = IntentDescription(
        "Makes a link anyone can open for a file or folder in one of your clouds, and copies it.",
        categoryName: "Sharing")

    @Parameter(title: "File", supportedContentTypes: [.item])
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Copy share link for \(\.$file)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<URL> & ProvidesDialog {
        guard let url = file.fileURL else { throw ShortcutError.noFile }
        let target = try await ShortcutTarget.resolve(url)
        guard !target.isTopFolder else { throw ShortcutError.topFolder }
        if CloudCapabilities.shared?.entries()[target.remote]?.shareLinks == false {
            throw ShortcutError.cannotShare(cloud: target.remote)
        }

        let services = try IntentServices.require()
        try await services.waitForDaemon()
        let expiry = await Self.defaultExpiry(remote: target.remote, monitor: services.cloudMonitor)
        let link: URL?
        do {
            link = try await services.daemon.client.publicLink(
                fs: "\(target.remote):", remote: target.path, expire: expiry?.duration)
        } catch {
            throw ShortcutError.service("Couldn't make a link: \(Self.firstLine(of: error))")
        }
        guard let link else { throw ShortcutError.noLink }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        return .result(value: link, dialog: "\(ShareLinkSupport.copiedCaption(expiry: expiry))")
    }

    @MainActor
    private static func defaultExpiry(remote: String, monitor: CloudMonitor) async -> ShareLinkSupport.Expiry? {
        if !monitor.hasLoaded { await monitor.refresh() }
        guard let cloud = monitor.remotes.first(where: { $0.name == remote }) else { return nil }
        return expiry(forBackend: CloudNaming.resolvedType(of: cloud, in: monitor.remotes))
    }

    /// Nil asks for a link with no expiry.
    static func expiry(forBackend type: String) -> ShareLinkSupport.Expiry? {
        let expiry = ShareLinkSupport.forBackend(type).defaultExpiry
        return expiry == .never ? nil : expiry
    }

    private static func firstLine(of error: Error) -> String {
        let text = error.localizedDescription
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}
