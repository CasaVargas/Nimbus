import SwiftUI
import RcloneKit

struct FileGrid: View {
    let files: [FileItem]
    @Binding var selection: Set<String>
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(files) { file in
                    VStack(spacing: 4) {
                        Image(systemName: file.isDir ? "folder.fill" : "doc")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(file.isDir ? .blue : .secondary)

                        Text(file.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 100, height: 90)
                    .padding(8)
                    .background(
                        selection.contains(file.path)
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .onTapGesture {
                        selection = [file.path]
                    }
                    .onTapGesture(count: 2) {
                        onOpen(file)
                    }
                    .contextMenu {
                        FileContextMenu(file: file, onAction: { action in
                            onContextAction(file, action)
                        })
                    }
                }
            }
            .padding()
        }
    }
}
