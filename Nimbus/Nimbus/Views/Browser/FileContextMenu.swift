import SwiftUI
import RcloneKit

enum FileAction {
    case open
    case rename
    case delete
}

struct FileContextMenu: View {
    let file: FileItem
    let onAction: (FileAction) -> Void

    var body: some View {
        Button("Open") { onAction(.open) }
        Divider()
        Button("Rename") { onAction(.rename) }
        Divider()
        Button("Delete", role: .destructive) { onAction(.delete) }
    }
}
