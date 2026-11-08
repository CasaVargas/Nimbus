import SwiftUI
import RcloneKit

/// Single Browser row, extracted verbatim from the FileTable column
/// closures so it can be hosted inside an AppKit NSTableView cell
/// (Phase 2d) while remaining the single source of truth for row
/// appearance. Fixed-height; no self-sizing (avoids NSHostingView /
/// NSTableView autolayout thrash).
struct FileRowView: View {
    let file: FileItem
    let remote: String
    let isSelected: Bool
    /// Whether the containing row's selection highlight is emphasized (key
    /// window + focused table). NSTableView paints the highlight itself —
    /// this view must NOT paint its own background; it only inverts text to
    /// white over the vibrant highlight, exactly like Finder. Unemphasized
    /// (inactive window) selection keeps normal label colors over gray.
    var isEmphasized: Bool = true

    static let rowHeight: CGFloat = 24
    static let iconSize: CGFloat = 16
    static let statusColumnWidth: CGFloat = 28
    static let dateColumnWidth: CGFloat = 120
    static let sizeColumnWidth: CGFloat = 80

    private var invertsText: Bool { isSelected && isEmphasized }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            CloudStatusColumn(file: file, remote: remote)
                .frame(width: Self.statusColumnWidth)
                .accessibilityLabel("Cloud status")

            Image(nsImage: FileIcon.image(for: file))
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)

            Text(file.name)
                .font(DesignSystem.Typography.body)
                .lineLimit(1)
                .foregroundStyle(invertsText
                                 ? Color.white
                                 : DesignSystem.Color.semantic.textPrimary)

            Spacer(minLength: DesignSystem.Spacing.m)

            Group {
                if let date = file.modTime {
                    Text(date, style: .date)
                        .foregroundStyle(invertsText
                                         ? Color.white.opacity(0.85)
                                         : DesignSystem.Color.semantic.textSecondary)
                } else {
                    Text("--")
                        .foregroundStyle(invertsText
                                         ? Color.white.opacity(0.7)
                                         : DesignSystem.Color.semantic.textTertiary)
                }
            }
            .font(DesignSystem.Typography.callout)
            .frame(width: Self.dateColumnWidth, alignment: .leading)

            Text(file.isDir ? "--" : Self.formatSize(file.size))
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(invertsText
                                 ? Color.white.opacity(0.85)
                                 : DesignSystem.Color.semantic.textSecondary)
                .frame(width: Self.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.s)
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
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

    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    VStack(spacing: 0) {
        FileRowView(
            file: FileItem(path: "/a/folder", name: "Documents", size: 0,
                           mimeType: "public.folder", modTime: Date(), isDir: true,
                           fileID: nil, qualifiedRemotePath: "r:/a/folder"),
            remote: "r", isSelected: false
        )
        FileRowView(
            file: FileItem(path: "/a/report.pdf", name: "report.pdf", size: 1_400_000,
                           mimeType: "application/pdf", modTime: Date(), isDir: false,
                           fileID: nil, qualifiedRemotePath: "r:/a/report.pdf"),
            remote: "r", isSelected: true
        )
        // The row no longer paints selection itself (NSTableView does), so
        // the preview supplies the system highlight for the selected row.
        .background(Color(nsColor: .selectedContentBackgroundColor))
    }
    .frame(width: 520)
}
