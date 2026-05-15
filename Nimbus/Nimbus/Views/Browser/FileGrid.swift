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

    private var sortedIDs: [String] { files.map(\.id) }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: DesignSystem.Spacing.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.m) {
                ForEach(files) { file in
                    tile(for: file)
                        .draggable(NimbusFileRef(
                            remoteName: remote,
                            path: file.path,
                            size: file.size,
                            isDir: file.isDir
                        )) {
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
        VStack(spacing: DesignSystem.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
                    .frame(width: 76, height: 76)
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
        }
        .padding(DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(isSelected
                      ? DesignSystem.Color.semantic.accent.opacity(0.18)
                      : .clear)
        )
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { onOpen(file) })
        .simultaneousGesture(TapGesture().onEnded {
            // Single-tap toggles selection. shift/cmd handling deferred to AppKit if needed.
            selection.select(file.id, in: sortedIDs)
        })
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
}
