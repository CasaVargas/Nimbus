import SwiftUI
import RcloneKit

/// File browser list. Renders the virtualized AppKit `FileTableView` via
/// `FileTableRepresentable`; selection/drag/keyboard/context-menu logic
/// lives in `FileTableCoordinator`. Public API is unchanged so the
/// `BrowserView` call site compiles untouched.
struct FileTable: View {
    let files: [FileItem]
    let remote: String
    @Bindable var selection: Selection<String>
    @Bindable var keyboard: KeyboardCoordinator
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    let onQuickLook: ([FileItem]) -> Void

    var body: some View {
        FileTableRepresentable(
            files: files,
            remote: remote,
            selection: selection,
            keyboard: keyboard,
            sortField: $sortField,
            sortAscending: $sortAscending,
            onOpen: onOpen,
            onContextAction: onContextAction,
            onQuickLook: onQuickLook
        )
    }
}
