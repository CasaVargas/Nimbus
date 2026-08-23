import SwiftUI
import RcloneKit

/// File browser grid (icon) view. Same foundation wiring as FileTable:
/// Selection<String> drives selection state and .draggable produces
/// NimbusFileRef payloads for cross-remote drag.
struct FileGrid: View {
    let files: [FileItem]
    let remote: String
    @Bindable var selection: Selection<String>
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    @State private var hoveredID: String?

    private var sortedIDs: [String] { files.map(\.id) }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: DesignSystem.Spacing.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.m) {
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
            .padding(DesignSystem.Spacing.m)
        }
    }

    @ViewBuilder
    private func tile(for file: FileItem) -> some View {
        let isSelected = selection.ids.contains(file.id)
        VStack(spacing: DesignSystem.Spacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(isSelected
                          ? DesignSystem.Color.semantic.selection.opacity(0.16)
                          : DesignSystem.Color.semantic.surfaceSubtle)
                    .frame(width: 76, height: 76)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                            .stroke(isSelected
                                    ? DesignSystem.Color.semantic.selection.opacity(0.55)
                                    : DesignSystem.Color.semantic.separator.opacity(hoveredID == file.id ? 0.7 : 0))
                    }
                Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(file.isDir
                                     ? DesignSystem.Color.semantic.statusInfo
                                     : DesignSystem.Color.semantic.textSecondary)
            }
            Text(file.name)
                .font(DesignSystem.Typography.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
            Text(file.isDir ? "Folder" : fileType(for: file.name))
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .lineLimit(1)
        }
        .padding(DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(isSelected
                      ? DesignSystem.Color.semantic.accent.opacity(0.18)
                      : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.snappy) {
                hoveredID = hovering ? file.id : nil
            }
        }
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
        Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
            .font(DesignSystem.Typography.largeTitle)
            .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
            .padding()
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

    private func fileType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        return ext.isEmpty ? "Document" : ext.uppercased()
    }
}
