import SwiftUI
import RcloneKit

struct FileTable: View {
    let files: [FileItem]
    @Binding var selection: Set<String>
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void

    var body: some View {
        Table(files, selection: $selection) {
            TableColumn("Name") { file in
                HStack(spacing: 8) {
                    Image(systemName: file.isDir ? "folder.fill" : iconName(for: file.name))
                        .foregroundStyle(file.isDir ? .blue : .secondary)
                    Text(file.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onOpen(file) }
            }

            TableColumn("Size") { file in
                Text(file.isDir ? "--" : formatSize(file.size))
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 80)

            TableColumn("Modified") { file in
                if let date = file.modTime {
                    Text(date, style: .date)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--").foregroundStyle(.secondary)
                }
            }
            .width(ideal: 120)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first, let file = files.first(where: { $0.path == path }) {
                FileContextMenu(file: file, onAction: { action in
                    onContextAction(file, action)
                })
            }
        } primaryAction: { paths in
            if let path = paths.first, let file = files.first(where: { $0.path == path }) {
                onOpen(file)
            }
        }
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
