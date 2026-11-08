import SwiftUI
import RcloneKit

struct Sidebar: View {
    @Binding var selection: SidebarSelection?
    @Environment(BookmarkStore.self) private var bookmarkStore
    var onBookmarkSelected: ((String, String) -> Void)?
    var onBookmarkDrop: ((_ bundles: [NimbusFileBundle], _ bookmark: FolderBookmark) -> Void)?

    var body: some View {
        List(selection: $selection) {
            Label("Home", systemImage: "house")
                .tag(SidebarSelection.home)

            RemotesSidebarSection()

            Section {
                Label("Copy Between Clouds", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarSelection.copySync)
            } header: {
                Text("Tools")
            }

            if !bookmarkStore.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        // HStack + .onTapGesture (not Button): a Button inside a
                        // List intercepts drag events and breaks .dropDestination.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.label)
                                Text("\(bookmark.remoteName):\(bookmark.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder.badge.star")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onBookmarkSelected?(bookmark.remoteName, bookmark.path)
                        }
                        .contextMenu {
                            Button("Remove Bookmark", role: .destructive) {
                                bookmarkStore.removeBookmark(id: bookmark.id)
                            }
                        }
                        .dropDestination(for: NimbusFileBundle.self) { bundles, _ in
                            onBookmarkDrop?(bundles, bookmark)
                            return true
                        }
                    }
                    .onMove { fromOffsets, toOffset in
                        bookmarkStore.reorder(fromOffsets: fromOffsets, toOffset: toOffset)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Nimbus")
    }
}
