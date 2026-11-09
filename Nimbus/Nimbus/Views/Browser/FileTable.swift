import SwiftUI
import RcloneKit

/// File browser list. Renders the virtualized AppKit `FileTableView` via
/// `FileTableRepresentable`; selection/drag/keyboard/context-menu logic
/// lives in `FileTableCoordinator`. Public API is unchanged so the
/// `BrowserView` call site compiles untouched.
struct FileTable: View {
    let files: [FileItem]
    let remote: String
    let selection: Selection<String>
    let keyboard: KeyboardCoordinator
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    let onQuickLook: ([FileItem]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileTableHeader(sortField: $sortField, sortAscending: $sortAscending)
            Divider()
            table
        }
    }

    private var table: some View {
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

/// Finder-style column headers for the list view. Laid out on the same
/// fixed widths as `FileRowView` so the labels sit over their columns; the
/// AppKit table below has its own header disabled because its single
/// column hosts the whole SwiftUI row.
struct FileTableHeader: View {
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool

    /// `NSTableView.Style.inset` indents row content from the scroll view
    /// edge; the header mirrors that so "Name" lines up with the names.
    private static let insetStyleMargin: CGFloat = 18

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Color.clear
                .frame(width: FileRowView.statusColumnWidth, height: 1)
            Color.clear
                .frame(width: FileRowView.iconSize, height: 1)
            header("Name", field: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: DesignSystem.Spacing.m)
            header("Date Modified", field: .modified, alignment: .leading)
                .frame(width: FileRowView.dateColumnWidth, alignment: .leading)
            header("Size", field: .size, alignment: .trailing)
                .frame(width: FileRowView.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.s + Self.insetStyleMargin)
        .frame(height: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Column headers")
    }

    private func header(_ title: LocalizedStringKey, field: SortField, alignment: HorizontalAlignment) -> some View {
        let isActive = sortField == field
        return Button {
            if isActive {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                if alignment == .trailing, isActive { chevron }
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive
                                     ? DesignSystem.Color.semantic.textPrimary
                                     : DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
                if alignment == .leading, isActive { chevron }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isActive ? (sortAscending ? "Sorted ascending" : "Sorted descending") : "")
        .accessibilityHint("Sorts the list by this column")
    }

    private var chevron: some View {
        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
            .resizable()
            .scaledToFit()
            .frame(width: 7, height: 7)
            .fontWeight(.bold)
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
    }
}
