import AppKit
import Foundation
import Quartz
import RcloneKit
import SwiftUI

// MARK: - MaterializationProvider

/// Strategy for turning a (`FileItem`, remote) pair into a local file URL that
/// Quick Look can preview. Two concrete strategies exist:
/// - `FileProviderMaterializationProvider` when the remote is mounted in
///   Finder via the File Provider extension (system handles materialization).
/// - `TempDownloadMaterializationProvider` when the remote is browsed in
///   Nimbus but not mounted; we copy the file to a temp location ourselves.
@MainActor
protocol MaterializationProvider: AnyObject {
    func resolveURL(for item: FileItem, remote: String) async throws -> URL
    /// Called when Quick Look closes — clean up any temp files this provider
    /// created during `resolveURL`.
    func dispose()
}

/// Returns a Finder-visible URL pointing at the File Provider mount. Reading
/// the URL lazily triggers materialization via `NSFileProviderManager`.
@MainActor
final class FileProviderMaterializationProvider: MaterializationProvider {
    private let bridge: FileProviderBridgeProtocol

    init(bridge: FileProviderBridgeProtocol) {
        self.bridge = bridge
    }

    func resolveURL(for item: FileItem, remote: String) async throws -> URL {
        // FileItem.path is the leaf name relative to the current listed dir.
        // FileItem.qualifiedRemotePath ("remote:dir/sub/leaf") encodes the full path from the remote root.
        // Strip the "remote:" prefix to get the path the FP-mounted root URL expects.
        let prefix = "\(remote):"
        let fullPath: String
        if item.qualifiedRemotePath.hasPrefix(prefix) {
            fullPath = String(item.qualifiedRemotePath.dropFirst(prefix.count))
        } else {
            // Best-effort fallback: use FileItem.path as-is.
            fullPath = item.path
        }
        guard let url = await bridge.urlForItem(remote: remote, path: fullPath) else {
            throw QuickLookError.cannotResolveFileProviderURL(remote: remote, path: fullPath)
        }
        return url
    }

    /// No-op — Finder/`NSFileProviderManager` owns the lifetime of files
    /// behind a mounted domain. Evicting them ourselves would step on the
    /// system's cache management.
    func dispose() {}
}

/// Downloads files to a per-resolve temp directory and tracks them for
/// cleanup when `dispose` is called.
@MainActor
final class TempDownloadMaterializationProvider: MaterializationProvider {
    private let client: RcloneClientProtocol
    private var createdDirs: [URL] = []

    init(client: RcloneClientProtocol) {
        self.client = client
    }

    func resolveURL(for item: FileItem, remote: String) async throws -> URL {
        let prefix = "\(remote):"
        let fullPath: String
        if item.qualifiedRemotePath.hasPrefix(prefix) {
            fullPath = String(item.qualifiedRemotePath.dropFirst(prefix.count))
        } else {
            fullPath = item.path
        }
        let url = try await client.downloadToTemp(remote: remote, path: fullPath)
        createdDirs.append(url.deletingLastPathComponent())
        return url
    }

    func dispose() {
        let dirs = createdDirs
        createdDirs.removeAll()
        for dir in dirs {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

enum QuickLookError: Error {
    case cannotResolveFileProviderURL(remote: String, path: String)
}

// MARK: - QuickLookHost

/// Owns the `QLPreviewPanel` data source/delegate and the lifetime of a
/// `MaterializationProvider` for the in-flight preview. Construct once per
/// browser window and call `show` to open a panel.
@MainActor
final class QuickLookHost: NSObject {
    /// Picks the right `MaterializationProvider` for a remote based on
    /// whether it's currently registered with the File Provider extension.
    /// Always downloads to a temp file via rclone. The File-Provider
    /// placeholder path was unreliable for types Quick Look can't render
    /// without the full bytes (e.g. audio: a registered remote's mp3
    /// opened blank because the placeholder was never materialized). A
    /// full temp download with the correct extension previews every type.
    static func provider(
        forRemote remote: String,
        bridge: FileProviderBridgeProtocol,
        client: RcloneClientProtocol
    ) -> MaterializationProvider {
        TempDownloadMaterializationProvider(client: client)
    }

    // Live preview state.
    private var items: [FileItem] = []
    private var urls: [URL] = []
    private var provider: MaterializationProvider?

    /// Resolves URLs for `items` via `provider`, then opens `QLPreviewPanel`.
    /// Errors during resolution leave the panel un-shown.
    func show(items: [FileItem], provider: MaterializationProvider, remote: String) async {
        // Dispose any provider from a prior invocation before taking ownership of the new one.
        teardownProvider()

        // Empty selection: do nothing rather than open an empty panel.
        guard !items.isEmpty else { return }

        self.items = items
        self.provider = provider

        do {
            urls = try await Self.resolveURLs(items: items, provider: provider, remote: remote)
        } catch {
            // Partial resolutions may have created temp files — clean them up.
            teardownProvider()
            return
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the preview panel and disposes the materialization provider so
    /// any temp files it created are removed.
    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
        teardownProvider()
    }

    /// Disposes any in-flight provider and clears resolved URLs.
    /// Called at the start of show() (re-entry) and on error paths.
    private func teardownProvider() {
        provider?.dispose()
        provider = nil
        urls = []
        items = []
    }

    /// Resolves URLs sequentially. Sequential rather than parallel because the
    /// `MaterializationProvider` is `@MainActor`-isolated (it tracks mutable
    /// state for cleanup), and Quick Look invocations are almost always a
    /// single file — the rare multi-select case is still bounded by typical
    /// network throughput rather than concurrency.
    private static func resolveURLs(
        items: [FileItem],
        provider: MaterializationProvider,
        remote: String
    ) async throws -> [URL] {
        var resolved: [URL] = []
        resolved.reserveCapacity(items.count)
        for item in items {
            let url = try await provider.resolveURL(for: item, remote: remote)
            resolved.append(url)
        }
        return resolved
    }
}

// MARK: - QLPreviewPanelDataSource

// `QLPreviewPanelDataSource` and `QLPreviewPanelDelegate` are AppKit Objective-C
// protocols that pre-date Swift concurrency. The panel only calls these methods
// on the main thread, so we mark each method `nonisolated` and use
// `MainActor.assumeIsolated` to access MainActor-isolated state safely.
extension QuickLookHost: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

// MARK: - QLPreviewPanelDelegate

extension QuickLookHost: QLPreviewPanelDelegate {
    nonisolated func previewPanel(_: QLPreviewPanel!, handle _: NSEvent!) -> Bool {
        // Defer to the panel's built-in arrow/escape handling.
        false
    }
}
