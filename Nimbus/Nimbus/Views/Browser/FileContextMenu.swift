import SwiftUI
import RcloneKit

enum FileAction {
    case open
    case rename
    case delete
    case bookmark
    case download
    case evict
    case share
}

struct FileContextMenu: View {
    let file: FileItem
    let onAction: (FileAction) -> Void
    /// False for fixed top-level folders.
    var allowsModifying = true

    var body: some View {
        Button("Open") { onAction(.open) }
        if file.isDir {
            Button {
                onAction(.bookmark)
            } label: {
                Label("Add to Bookmarks", systemImage: "folder.badge.star")
            }
        }
        // Download Now / Remove Local Copy are intentionally absent until
        // the NSFileProviderManager materialize/evict calls are wired —
        // dead menu items erode trust faster than missing ones.
        if !file.isDir {
            Button {
                onAction(.share)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        if allowsModifying {
            Divider()
            Button("Rename") { onAction(.rename) }
            Divider()
            Button("Delete", role: .destructive) { onAction(.delete) }
        }
    }
}
