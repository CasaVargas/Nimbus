import SwiftUI
import RcloneKit

enum FileAction {
    case open
    case rename
    case delete
    case bookmark
    case download
    case evict
}

struct FileContextMenu: View {
    let file: FileItem
    let onAction: (FileAction) -> Void

    var body: some View {
        Button("Open") { onAction(.open) }
        if file.isDir {
            Button {
                onAction(.bookmark)
            } label: {
                Label("Add to Bookmarks", systemImage: "folder.badge.star")
            }
        }
        if !file.isDir {
            Divider()
            Button {
                onAction(.download)
            } label: {
                Label("Download Now", systemImage: "arrow.down.circle")
            }
            Button {
                onAction(.evict)
            } label: {
                Label("Remove Local Copy", systemImage: "cloud")
            }
        }
        Divider()
        Button("Rename") { onAction(.rename) }
        Divider()
        Button("Delete", role: .destructive) { onAction(.delete) }
    }
}
