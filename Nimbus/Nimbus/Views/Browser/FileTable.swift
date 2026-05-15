import SwiftUI
import RcloneKit

/// File browser table view. Wires foundation primitives:
/// - Selection<String> drives multi-select with Finder semantics
/// - KeyboardCoordinator handles space/return/delete + type-to-select
/// - .draggable produces NimbusFileRef payloads for cross-remote drag
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

    private var sortedIDs: [String] { files.map(\.id) }

    // NOTE: SwiftUI Table re-sets the entire selection on each click, so Selection's
    // anchor is overwritten by `replace(with:in:)` rather than tracking the actual
    // click point. Keyboard ops (handled below) set anchor correctly; shift-arrow
    // extension across mixed mouse+keyboard input would need an AppKit bridge.
    private var tableSelectionBinding: Binding<Set<String>> {
        Binding(
            get: { selection.ids },
            set: { newSet in selection.replace(with: newSet, in: sortedIDs) }
        )
    }

    var body: some View {
        Table(files, selection: tableSelectionBinding) {
            TableColumn("") { file in
                CloudStatusColumn(file: file)
                    .accessibilityLabel("Cloud status")
            }
            .width(28)

            TableColumn("Name") { file in
                HStack(spacing: DesignSystem.Spacing.s) {
                    Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
                        .foregroundStyle(file.isDir
                                         ? DesignSystem.Color.semantic.statusInfo
                                         : DesignSystem.Color.semantic.textSecondary)
                    Text(file.name)
                        .font(DesignSystem.Typography.body)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .draggable(NimbusFileRef(
                    remoteName: remote,
                    path: file.path,
                    size: file.size,
                    isDir: file.isDir
                )) {
                    dragPreview(for: file)
                }
            }

            TableColumn("Size") { file in
                Text(file.isDir ? "--" : formatSize(file.size))
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            .width(ideal: 80)

            TableColumn("Modified") { file in
                if let date = file.modTime {
                    Text(date, style: .date)
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                } else {
                    Text("--")
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
            }
            .width(ideal: 120)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                FileContextMenu(file: file, onAction: { action in onContextAction(file, action) })
            }
        } primaryAction: { ids in
            if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                onOpen(file)
            }
        }
        .focusable(true)
        .onKeyPress(phases: .down) { press in
            handleKey(press: press)
        }
    }

    private func handleKey(press: KeyPress) -> KeyPress.Result {
        let ordering = sortedIDs

        // Type-to-select first (letter/digit + common filename chars).
        if let c = press.characters.first,
           c.isLetter || c.isNumber || ".-_".contains(c) {
            keyboard.handleTypeToSelect(char: c, against: files.map(\.name)) { matchedName in
                if let f = files.first(where: { $0.name == matchedName }) {
                    selection.select(f.id, in: ordering)
                }
            }
            return .handled
        }

        switch press.key {
        case .space:
            // Trigger Quick Look on the current selection.
            let items = files.filter { selection.ids.contains($0.id) }
            if !items.isEmpty {
                onQuickLook(items)
            }
            return .handled
        case .return:
            if let id = selection.anchor, let f = files.first(where: { $0.id == id }) {
                onOpen(f)
            }
            return .handled
        case .delete:
            if let id = selection.anchor, let f = files.first(where: { $0.id == id }) {
                onContextAction(f, .delete)
            }
            return .handled
        default:
            return .ignored
        }
    }

    @ViewBuilder
    private func dragPreview(for file: FileItem) -> some View {
        let count = max(1, selection.ids.count)
        ZStack(alignment: .topTrailing) {
            Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
            if count > 1 {
                Text("\(count)")
                    .font(DesignSystem.Typography.captionEmphasized)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(DesignSystem.Color.semantic.statusError))
                    .foregroundStyle(.white)
                    .offset(x: 6, y: -6)
            }
        }
        .padding(DesignSystem.Spacing.s)
    }

    private func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aac": return "music.note"
        case "zip", "tar", "gz": return "archivebox"
        case "txt", "md": return "doc.text"
        default: return "doc"
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
