import SwiftUI
import RcloneKit

/// File browser grid (icon) view. Same foundation wiring as FileTable:
/// Selection<String> drives selection state and .draggable produces
/// NimbusFileRef payloads for cross-remote drag.
struct FileGrid: View {
    enum Layout {
        static let cellWidth: CGFloat = 112
        static let iconSize: CGFloat = 48
        static let horizontalSpacing: CGFloat = DesignSystem.Spacing.s
        static let verticalSpacing: CGFloat = DesignSystem.Spacing.m
        static let column = GridItem(
            .adaptive(minimum: cellWidth, maximum: cellWidth),
            spacing: horizontalSpacing,
            alignment: .top
        )
    }

    let files: [FileItem]
    let remote: String
    @Bindable var selection: Selection<String>
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    private var sortedIDs: [String] { files.map(\.id) }

    private let columns = [Layout.column]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: Layout.verticalSpacing
            ) {
                ForEach(files) { file in
                    tile(for: file)
                        .draggable(bundle(for: file)) {
                            tilePreview(for: file)
                        }
                        .contextMenu {
                            FileContextMenu(file: file, onAction: { action in
                                onContextAction(file, action)
                            })
                        }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.l)
            .padding(.vertical, DesignSystem.Spacing.m)
        }
    }

    @ViewBuilder
    private func tile(for file: FileItem) -> some View {
        let isSelected = selection.ids.contains(file.id)
        FileGridTile(file: file, isSelected: isSelected)
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { onOpen(file) })
        .simultaneousGesture(TapGesture().onEnded {
            // Single-tap toggles selection. shift/cmd handling deferred to AppKit if needed.
            selection.select(file.id, in: sortedIDs)
        })
    }

    /// Builds the drag payload. If the dragged file is part of the current selection,
    /// bundle all selected files together. Otherwise just this single file.
    private func bundle(for file: FileItem) -> NimbusFileBundle {
        let isInSelection = selection.ids.contains(file.id)
        let sourceFiles: [FileItem] = isInSelection
            ? files.filter { selection.ids.contains($0.id) }
            : [file]
        let refs = sourceFiles.map {
            NimbusFileRef(remoteName: remote, path: $0.path, size: $0.size, isDir: $0.isDir)
        }
        return NimbusFileBundle(refs: refs)
    }

    @ViewBuilder
    private func tilePreview(for file: FileItem) -> some View {
        Image(nsImage: FileIcon.image(for: file))
            .resizable()
            .interpolation(.high)
            .frame(width: Layout.iconSize, height: Layout.iconSize)
            .padding()
    }

    static func iconName(for filename: String) -> String {
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

}

struct FileGridTile: View {
    let file: FileItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: FileIcon.image(for: file))
                .resizable()
                .interpolation(.high)
                .frame(width: FileGrid.Layout.iconSize, height: FileGrid.Layout.iconSize)
                .accessibilityHidden(true)
                .frame(height: 54)

            Text(file.name)
                .font(DesignSystem.Typography.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
        }
        .frame(width: FileGrid.Layout.cellWidth)
        .padding(.vertical, DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
                .fill(isSelected
                      ? DesignSystem.Color.semantic.selection.opacity(0.22)
                      : (isHovered ? DesignSystem.Color.semantic.surfaceSubtle : .clear))
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.snappy) {
                isHovered = hovering
            }
        }
    }
}
