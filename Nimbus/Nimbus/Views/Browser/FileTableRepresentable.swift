import SwiftUI
import AppKit
import RcloneKit

/// Bridges the virtualized AppKit `FileTableView` into SwiftUI. All list
/// behavior (selection, drag source, keyboard, context menu) lives in
/// `FileTableCoordinator`; this representable just builds the NSScrollView
/// and feeds the latest inputs through `updateNSView`.
///
/// `updateNSView` calls `coordinator.reloadPreservingSelection()` (NOT
/// `tableView.reloadData()`): a raw reload fires NSTableView's
/// selection-cleared notification while `isApplyingSelection == false`,
/// which would wipe the model selection via `tableViewSelectionDidChange`'s
/// else-branch. `reloadPreservingSelection()` brackets the reload in the
/// echo guard and restores selection atomically.
struct FileTableRepresentable: NSViewRepresentable {
    let files: [FileItem]
    let remote: String
    let selection: Selection<String>
    let keyboard: KeyboardCoordinator
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    let onQuickLook: ([FileItem]) -> Void

    @Environment(TransferStore.self) private var transferStore
    @Environment(FileProviderBridge.self) private var fileProviderBridge

    func makeCoordinator() -> FileTableCoordinator {
        FileTableCoordinator(
            selection: selection,
            keyboard: keyboard,
            onOpen: onOpen,
            onContextAction: onContextAction,
            onQuickLook: onQuickLook,
            onSortHeaderClick: { field in
                if sortField == field { sortAscending.toggle() }
                else { sortField = field; sortAscending = true }
            }
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = false
        // The table draws on the tab's glass, not on its own fill.
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.rowHeight = FileRowView.rowHeight
        table.headerView = nil

        func column(_ id: String, _ title: String, width: CGFloat) -> NSTableColumn {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = width
            return c
        }
        table.addTableColumn(column("row", "Name", width: 480))

        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.keyResponder = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(FileTableCoordinator.handleDoubleClick(_:))
        context.coordinator.tableView = table
        table.setDraggingSourceOperationMask([.copy], forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        // Cheap reference/string inputs: may legitimately change per render
        // (closures captured fresh each body pass, env objects), always apply.
        coord.remote = remote
        coord.onOpen = onOpen
        coord.onContextAction = onContextAction
        coord.onQuickLook = onQuickLook
        coord.transferStore = transferStore
        coord.fileProviderBridge = fileProviderBridge
        // Only reassign `files` (O(n) rebuildRowIndex didSet) and reload the
        // table when the file list actually changed. SwiftUI re-invokes
        // updateNSView on every re-render; during an active transfer over a
        // large directory TransferStore observation cascades re-renders, so
        // an unguarded reload would replay a full 10k reloadData per tick.
        if coord.applyFilesIfChanged(files) {
            coord.reloadPreservingSelection()
        }
    }
}
