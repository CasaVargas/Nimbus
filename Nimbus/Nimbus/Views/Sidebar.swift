import SwiftUI
import RcloneKit

struct Sidebar: View {
    @Binding var selection: SidebarSelection?
    @Environment(BookmarkStore.self) private var bookmarkStore
    var onRemotesLoaded: ([Remote]) -> Void
    var onBookmarkSelected: ((String, String) -> Void)?
    var onBookmarkDrop: ((_ bundles: [NimbusFileBundle], _ bookmark: FolderBookmark) -> Void)?

    var body: some View {
        List(selection: $selection) {
            RemotesSidebarSection(onRemotesLoaded: onRemotesLoaded)

            Section {
                Label("Copy & Sync", systemImage: "arrow.triangle.2.circlepath")
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusBar()
        }
    }
}

private struct SidebarStatusBar: View {
    @Environment(RcloneDaemon.self) private var daemon

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: DesignSystem.Spacing.s) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Spacing.m)
            .frame(height: 34)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("rclone status: \(statusText)")
        }
    }

    private var statusText: String {
        switch daemon.status {
        case .idle: "Not connected"
        case .starting: "Connecting…"
        case .connected: "rclone connected"
        case .error: "Connection issue"
        }
    }

    private var statusColor: Color {
        switch daemon.status {
        case .idle: DesignSystem.Color.semantic.statusMuted
        case .starting: DesignSystem.Color.semantic.statusWarning
        case .connected: DesignSystem.Color.semantic.statusOK
        case .error: DesignSystem.Color.semantic.statusError
        }
    }
}
