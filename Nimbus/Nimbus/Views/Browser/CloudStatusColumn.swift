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
    /// Adds the state in words after the glyph: the file table's
    /// "On this Mac" column.
    var showsLabel = false
    /// True on a selected, emphasized row, where text turns white.
    var isInverted = false

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
    /// Pinned with Keep Downloaded (directly or through a folder).
    @State private var isKept = false

    var body: some View {
        HStack(spacing: 3) {
            if isKept && style == .compact {
                Image(systemName: "pin.fill")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .help("Kept on this Mac")
                    .accessibilityLabel("Kept on this Mac")
            }
            StatusBadge(state: state, style: style)
            if showsLabel {
                // The compact badge draws nothing for a local file (a calm
                // column of glyphs); with words beside it, say it with a mark.
                if state == .local, !file.isDir, !isKept {
                    Image(systemName: "checkmark")
                        .font(DesignSystem.Typography.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(isInverted ? Color.white : DesignSystem.Color.semantic.statusOK)
                        .accessibilityHidden(true)
                }
                Text(verbatim: CloudStatusLabel.text(state: state, isKept: isKept, isDirectory: file.isDir))
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(isInverted ? Color.white.opacity(0.85) : DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
            }
        }
        .task(id: queryKey) {
            refreshKept()
            let materialized = await bridge.isItemMaterialized(remote: remote, path: file.path)
            let evicted = await bridge.wasRecentlyEvicted(remote: remote, path: file.path)
            isMaterialized = materialized
            isEvicted = evicted
        }
        .onReceive(NotificationCenter.default.publisher(for: .nimbusPinsChanged)) { _ in refreshKept() }
    }

    private func refreshKept() {
        let identifier = "\(remote):\(file.path)"
        let pins = PinStore.shared?.pins(domain: remote) ?? []
        isKept = pins.contains(identifier) || PinPolicy.keptByAncestor(
            identifier, pins: pins, rootKey: PinPolicy.rootKey)
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

/// The words for a file's state in the "On this Mac" column. Pure, so every
/// case is unit tested.
enum CloudStatusLabel {
    static func text(state: CloudStatus, isKept: Bool, isDirectory: Bool) -> String {
        if case .downloading(let progress) = state {
            return "Copying \(Int((progress * 100).rounded()))%"
        }
        if case .error = state { return "Problem" }
        if isKept { return "Kept on this Mac" }
        if isDirectory { return "--" }
        switch state {
        case .local: return "Downloaded"
        case .cloud, .evicted: return "In cloud"
        case .downloading, .error: return ""
        }
    }
}
