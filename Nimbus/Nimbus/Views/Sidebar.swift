import SwiftUI
import RcloneKit

struct Sidebar: View {
    @Binding var selection: SidebarSelection?
    @Environment(BookmarkStore.self) private var bookmarkStore
    var onBookmarkSelected: ((String, String) -> Void)?
    var onBookmarkDrop: ((_ bundles: [NimbusFileBundle], _ bookmark: FolderBookmark) -> Void)?

    var body: some View {
        List(selection: $selection) {
            SidebarToolLabel(title: "Home", systemImage: "house.fill", color: Colors.home)
                .tag(SidebarSelection.home)

            RemotesSidebarSection()

            Section {
                SidebarToolLabel(title: "Backups", systemImage: "clock.arrow.circlepath", color: Colors.backups)
                    .tag(SidebarSelection.backups)
                SidebarToolLabel(title: "Copy Between Clouds", systemImage: "arrow.left.arrow.right", color: Colors.copy)
                    .tag(SidebarSelection.copySync)
                SidebarToolLabel(title: "Compare Folders", systemImage: "rectangle.on.rectangle", color: Colors.compare)
                    .tag(SidebarSelection.compare)
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
        // The window's backdrop shows through the sidebar.
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStorageFooter()
                .padding(DesignSystem.Spacing.s)
        }
        .navigationTitle("Nimbus")
    }

    private typealias Colors = DesignSystem.Stratosphere.CloudColors
}

/// A sidebar row that isn't a cloud: a coloured icon tile and a title, the
/// same height and rhythm as `SidebarRemoteRow`.
struct SidebarToolLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: DesignSystem.Stratosphere.CloudColor

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            IconTile(systemImage: systemImage, color: color)
            Text(title)
                .font(DesignSystem.Stratosphere.Typography.control)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

/// Total free space and every cloud's share of storage, pinned to the
/// bottom of the sidebar. Hidden until at least one cloud reports usage.
struct SidebarStorageFooter: View {
    @Environment(CloudMonitor.self) private var monitor
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(\.cloudColors) private var cloudColors

    var body: some View {
        let quotas = monitor.remotes.compactMap { remote in
            statusService.quotas[remote.name].map { (name: remote.name, quota: $0) }
        }
        SidebarStorageSummary(
            totals: StorageTotals(quotas: quotas.map(\.quota)),
            clouds: quotas.map { (name: $0.name, quota: $0.quota, color: cloudColors[$0.name]) }
        )
    }
}

/// The footer's drawing, apart from where its numbers come from, so
/// previews can feed it demo data.
struct SidebarStorageSummary: View {
    let totals: StorageTotals
    let clouds: [(name: String, quota: StorageQuota, color: DesignSystem.Stratosphere.CloudColor?)]

    @Environment(\.stratosphere) private var palette

    var body: some View {
        if let usedFraction = totals.usedFraction {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: headline)
                        .font(DesignSystem.Stratosphere.Typography.sectionTitle)
                        .foregroundStyle(palette.textPrimary.color)
                    Spacer(minLength: DesignSystem.Spacing.s)
                    Text("\(usedFraction, format: .percent.precision(.fractionLength(0))) used")
                        .font(DesignSystem.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(palette.textTertiary.color)
                }
                SegmentBar(segments: clouds.map {
                    .init(id: $0.name, fraction: totals.share(of: $0.quota),
                          color: $0.color ?? DesignSystem.Stratosphere.CloudColors.sequence[0])
                })
            }
            .padding(DesignSystem.Spacing.m)
            .glassSurface(radius: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "All clouds: \(headline)"))
        }
    }

    /// Free space when any cloud has a limit; otherwise what's used, because
    /// pay-as-you-go storage has no "free".
    private var headline: String {
        if let free = totals.freeBytes { return "\(ByteText.format(free)) free" }
        return "\(ByteText.format(totals.usedBytes)) used"
    }
}
