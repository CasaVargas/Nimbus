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
        guard let url = await bridge.urlForItem(remote: remote, path: item.path) else {
            throw QuickLookError.cannotResolveFileProviderURL(remote: remote, path: item.path)
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
        let url = try await client.downloadToTemp(remote: remote, path: item.path)
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
    static func provider(
        forRemote remote: String,
        bridge: FileProviderBridgeProtocol,
        client: RcloneClientProtocol
    ) -> MaterializationProvider {
        if bridge.isRegistered(remote: remote) {
            return FileProviderMaterializationProvider(bridge: bridge)
        }
        return TempDownloadMaterializationProvider(client: client)
    }

    // Live preview state.
    private var items: [FileItem] = []
    private var urls: [URL] = []
    private var provider: MaterializationProvider?

    /// Resolves URLs for `items` via `provider`, then opens `QLPreviewPanel`.
    /// Errors during resolution leave the panel un-shown.
    func show(items: [FileItem], provider: MaterializationProvider, remote: String) async {
        self.items = items
        self.provider = provider

        do {
            urls = try await Self.resolveURLs(items: items, provider: provider, remote: remote)
        } catch {
            urls = []
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
        provider?.dispose()
        provider = nil
        items = []
        urls = []
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
// protocols that pre-date Swift concurrency, so they are unisolated. The panel
// itself only calls these methods on the main thread, so the bridge is safe
// when we annotate the methods nonisolated and hop back to the MainActor for
// any state access. `@preconcurrency` keeps the compiler from refusing the
// conformance entirely.
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
