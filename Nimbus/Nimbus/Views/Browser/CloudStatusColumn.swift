import SwiftUI
import RcloneKit

/// Renders the cloud-status indicator for a single Browser row.
/// Maps the row's (remote, path) state to a `CloudStatus`:
/// - Active matching transfer → `.downloading(progress:)`
/// - File Provider materialized → `.local`
/// - File Provider recently evicted → `.evicted`
/// - Default → `.cloud` (or `.local` for directories)
struct CloudStatusColumn: View {
    let file: FileItem
    let remote: String
    var style: StatusBadge.Style = .compact

    @Environment(TransferStore.self) private var transferStore
    @Environment(FileProviderBridge.self) private var bridge

    /// FP-materialized flag, refreshed in `.task` since the bridge query is
    /// async (it walks `NSFileProviderManager.enumeratorForMaterializedItems`).
    /// The bridge caches results for 5s per-remote so the per-row task is cheap.
    @State private var isMaterialized = false
    /// FP-evicted flag. Currently always `false` (no evicted-set enumerator
    /// on the SDK), kept as a `@State` for forward-compatibility with the
    /// async protocol.
    @State private var isEvicted = false

    var body: some View {
        StatusBadge(state: state, style: style)
            .task(id: queryKey) {
                let materialized = await bridge.isItemMaterialized(remote: remote, path: file.path)
                let evicted = await bridge.wasRecentlyEvicted(remote: remote, path: file.path)
                isMaterialized = materialized
                isEvicted = evicted
            }
    }

    /// Re-fire the FP-status task only when the row identity changes.
    /// Avoids re-querying when transfer progress ticks redraw the row.
    private var queryKey: String { "\(remote)|\(file.path)" }

    private var state: CloudStatus {
        // Directories don't have meaningful cloud status — show .local so
        // users see a stable visual for folder rows.
        if file.isDir { return .local }

        // Active transfer matching this file's destination?
        if let progress = activeProgress() {
            return .downloading(progress: progress)
        }

        // FP-materialized → local
        if isMaterialized {
            return .local
        }

        // Recently evicted → evicted state
        if isEvicted {
            return .evicted
        }

        // Default
        return .cloud
    }

    /// Returns progress (0...1) if any active transfer's destination matches
    /// this file. `DragDropCoordinator` builds `dstFs` as
    /// `<remote>:<dest-path>/<filename>`, so we match the exact
    /// `"<remote>:<path>"` form first and fall back to a remote-scoped
    /// filename match. The remote prefix ensures a transfer destined for
    /// `s3:/Backup/foo.jpg` doesn't bleed into a `gdrive:/Backup/foo.jpg`
    /// row with the same filename.
    private func activeProgress() -> Double? {
        let expected = "\(remote):\(file.path)"
        for t in transferStore.transfers where t.status.isActive {
            // Exact match against "<remote>:<path>" first (DragDropCoordinator's dstFs format),
            // then a fallback that still scopes to this remote's path.
            if t.dstFs == expected || t.dstFs.hasPrefix("\(remote):") && t.dstFs.hasSuffix("/\(file.name)") {
                return t.progress
            }
        }
        return nil
    }
}
