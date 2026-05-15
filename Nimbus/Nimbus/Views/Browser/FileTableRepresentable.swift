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
        context.coordinator.tableView = table
        table.setDraggingSourceOperationMask([.copy], forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.files = files
        coord.remote = remote
        coord.onOpen = onOpen
        coord.onContextAction = onContextAction
        coord.onQuickLook = onQuickLook
        coord.reloadPreservingSelection()
    }
}
