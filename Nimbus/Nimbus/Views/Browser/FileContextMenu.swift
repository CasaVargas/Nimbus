import SwiftUI
import RcloneKit

enum FileAction {
    case open
    case rename
    case delete
    case bookmark
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
        Divider()
        Button("Rename") { onAction(.rename) }
        Divider()
        Button("Delete", role: .destructive) { onAction(.delete) }
    }
}
