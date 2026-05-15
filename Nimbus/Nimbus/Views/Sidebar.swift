import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case remotes = "Remotes"
    case mounts = "Mounts"
    case transfers = "Transfers"
    case copySync = "Copy / Sync"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .remotes: "cloud"
        case .mounts: "externaldrive"
        case .transfers: "arrow.up.arrow.down"
        case .copySync: "doc.on.doc"
        case .settings: "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(BookmarkStore.self) private var bookmarkStore
    var onBookmarkSelected: ((String, String) -> Void)?
    var onBookmarkDrop: ((_ bundles: [NimbusFileBundle], _ bookmark: FolderBookmark) -> Void)?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

            if !bookmarkStore.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        // Use HStack with .contentShape + .onTapGesture instead of Button.
                        // Button-inside-List intercepts drag-and-drop events, preventing
                        // .dropDestination from firing.
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
