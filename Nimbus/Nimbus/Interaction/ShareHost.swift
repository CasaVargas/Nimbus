import AppKit
import Observation
import RcloneKit
import os

extension FileItem {
    /// Full path from the remote's root. `path` is relative to the listed
    /// folder; the qualified path ("remote:dir/leaf") carries the full one.
    func pathFromRoot(remote: String) -> String {
        let prefix = "\(remote):"
        return qualifiedRemotePath.hasPrefix(prefix) ? String(qualifiedRemotePath.dropFirst(prefix.count)) : path
    }
}

/// Share… for cloud files: downloads them to a temp folder the way Quick
/// Look does, then shows the system share picker (Mail, Messages, AirDrop…).
@Observable
@MainActor
final class ShareHost {
    static let shared = ShareHost()

    /// True while files are downloading, so the browser can say so.
    private(set) var isPreparing = false
    /// Downloads from the last share. The service the user picks reads the
    /// files after the picker closes, so they're kept until the next share
    /// or quit rather than deleted on dismissal.
    private var tempDirectories: [URL] = []
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "share")

    func share(_ items: [FileItem], remote: String, client: any RcloneClientProtocol) async {
        let files = items.filter { !$0.isDir }
        guard !files.isEmpty, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let urls = try await materialize(files, remote: remote, client: client)
            present(urls)
        } catch {
            logger.error("Share failed: \(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = files.count == 1 ? "Couldn't get “\(files[0].name)” ready to share" : "Couldn't get the files ready to share"
            alert.informativeText = NimbusError.classify(error).message
            alert.runModal()
        }
    }

    /// Downloads each file to its own temp folder, replacing the last
    /// share's downloads. On failure nothing is left behind.
    func materialize(_ files: [FileItem], remote: String, client: any RcloneClientProtocol) async throws -> [URL] {
        dispose()
        var urls: [URL] = []
        do {
            for file in files {
                let url = try await client.downloadToTemp(remote: remote, path: file.pathFromRoot(remote: remote))
                tempDirectories.append(url.deletingLastPathComponent())
                urls.append(url)
            }
        } catch {
            dispose()
            throw error
        }
        return urls
    }

    func dispose() {
        for directory in tempDirectories { try? FileManager.default.removeItem(at: directory) }
        tempDirectories = []
    }

    private func present(_ urls: [URL]) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView else { return }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        NSSharingServicePicker(items: urls)
            .show(relativeTo: CGRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }
}
