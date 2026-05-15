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

    @Environment(TransferStore.self) private var transferStore
    @Environment(FileProviderBridge.self) private var bridge

    var body: some View {
        StatusBadge(state: state)
    }

    private var state: CloudStatus {
        // Directories don't have meaningful cloud status — show .local so
        // users see a stable visual for folder rows.
        if file.isDir { return .local }

        // Active transfer matching this file's destination?
        if let progress = activeProgress() {
            return .downloading(progress: progress)
        }

        // FP-materialized → local
        if bridge.isItemMaterialized(remote: remote, path: file.path) {
            return .local
        }

        // Recently evicted → evicted state
        if bridge.wasRecentlyEvicted(remote: remote, path: file.path) {
            return .evicted
        }

        // Default
        return .cloud
    }

    /// Returns progress (0...1) if any active transfer's destination matches
    /// this file. Match heuristic: `dstFs` ends with the file's path.
    /// `DragDropCoordinator` builds `dstFs` as `<remote>:<dest-path>/<filename>`
    /// so the suffix match is sufficient.
    private func activeProgress() -> Double? {
        for t in transferStore.transfers where t.status.isActive {
            if t.dstFs.hasSuffix(file.path) || t.dstFs.hasSuffix("/\(file.name)") {
                return t.progress
            }
        }
        return nil
    }
}
