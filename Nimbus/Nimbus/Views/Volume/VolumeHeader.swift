import SwiftUI
import RcloneKit

/// Identity row of a volume pane: provider badge, name, one-line facts, and
/// the three verbs that matter. Reference: Disk Utility's volume header.
struct VolumeHeader: View {
    let remote: Remote
    /// Backend type for the badge; an alias passes the type it points at.
    var badgeType: String? = nil
    let providerName: String
    let quota: StorageQuota?
    let status: RemoteStatus
    let isInFinder: Bool
    let onPrimary: () -> Void
    let onSync: () -> Void
    let onEdit: () -> Void

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors

    private typealias S = DesignSystem.Stratosphere

    private var provider: String { badgeType ?? remote.type }

    private var color: S.CloudColor {
        cloudColors[remote.name] ?? S.CloudColors.color(forProvider: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LogoTile(provider: provider, size: .large)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.name)
                        .font(S.Typography.pageTitle)
                        .foregroundStyle(palette.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: subtitle)
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                }

                Spacer(minLength: DesignSystem.Spacing.l)

                HStack(spacing: DesignSystem.Spacing.s) {
                    Button(isInFinder ? "Open in Finder" : "Show in Finder", action: onPrimary)
                        .buttonStyle(.primaryPill(.small))
                    Button("Copy To…", action: onSync)
                        .buttonStyle(.glassCapsule)
                    Button("Edit", action: onEdit)
                        .buttonStyle(.glassCapsule)
                }
            }
            if let quota, let fraction = quota.fraction {
                usage(quota, fraction: fraction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassSurface(radius: S.Radius.header, tint: color)
    }

    /// How full the cloud is: a bar in its colour, then the numbers. Only
    /// drawn when the backend reports a total.
    private func usage(_ quota: StorageQuota, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            UsageBar(fraction: fraction, color: quota.isNearlyFull ? S.CloudColors.nearlyFull : color, height: 12)
            HStack(spacing: DesignSystem.Spacing.m) {
                Text(verbatim: "\(quota.usedText ?? "--") used")
                    .font(S.Typography.label)
                    .foregroundStyle(palette.textPrimary.color)
                Text(verbatim: "\(quota.freeText ?? "--") free")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
                Spacer()
                Text("\(fraction, format: .percent.precision(.fractionLength(0))) full")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage: \(quota.usedText ?? "unknown") used of \(quota.totalText ?? "unknown")")
    }

    private var subtitle: String {
        var parts: [String] = [providerName]
        // With a limit, the bar below carries the numbers. Without one,
        // this line is the only place usage shows.
        if let quota, quota.fraction == nil, let used = quota.usedText {
            parts.append("\(used) used")
        }
        switch status {
        case .authNeeded, .unreachable, .error: parts.append(status.shortText)
        case .unknown, .connected: parts.append(isInFinder ? "Shown in Finder" : "Not in Finder")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    VolumeHeader(
        remote: Remote(name: "Personal Drive", type: "drive", config: [:]),
        providerName: "Google Drive",
        quota: StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000),
        status: .connected,
        isInFinder: true,
        onPrimary: {}, onSync: {}, onEdit: {}
    )
    .padding()
    .frame(width: 760)
    .background { StratosphereBackdrop() }
}

#if DEBUG
/// The volume pane on its Finder tab, composed from the same parts the live
/// pane uses, with demo data. Rendered for the website and README screenshots
/// (docs/screenshots/volume-finder.png), where the page adds the window chrome.
#Preview("Volume pane, Finder tab", traits: .fixedLayout(width: 1000, height: 560)) {
    @Previewable @State var tab: VolumeTab = .finder
    let remote = Remote(name: "Personal Drive", type: "drive", config: [:])
    let quota = StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000)
    let inFinder = MountConfig(remote: "Personal Drive:", mountPoint: "", vfsMode: .readWrite, autoMount: true, backend: .fileProvider)
    let asVolume = MountConfig(remote: "Personal Drive:", mountPoint: "/Volumes/Personal Drive", vfsMode: .readWrite, autoMount: false, backend: .nfs)
    VolumePaneLayout {
        VolumeHeader(
            remote: remote,
            providerName: "Google Drive",
            quota: quota,
            status: .connected,
            isInFinder: true,
            onPrimary: {}, onSync: {}, onEdit: {}
        )
        VolumeTabBar(selection: $tab)
        List {
            MountRow(config: inFinder, state: .on, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}, inCloudPane: true)
            MountRow(config: asVolume, state: .off, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}, inCloudPane: true)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .glassContentSurface()
    }
    .background { StratosphereBackdrop() }
    .preferredColorScheme(.dark)
}

// MARK: - Demo windows for screenshots

/// A stand-in for the app window: the real sidebar rows and the real detail
/// views, with demo data and a drawn-in toolbar, so the website can show the
/// interface without a live rclone. Not part of the shipping app.
struct DemoWindow<Content: View>: View {
    let title: String
    let selection: SidebarSelection
    @ViewBuilder let content: () -> Content

    static var remotes: [(Remote, RemoteStatus, StorageQuota?)] {
        [
            (Remote(name: "Personal", type: "drive", config: [:]), .connected, StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000)),
            (Remote(name: "Work", type: "onedrive", config: [:]), .authNeeded, StorageQuota(used: 412_000_000_000, total: 1_000_000_000_000)),
            (Remote(name: "Dropbox", type: "dropbox", config: [:]), .connected, StorageQuota(used: 61_000_000_000, total: 2_000_000_000_000)),
            (Remote(name: "Photo Archive", type: "b2", config: [:]), .connected, StorageQuota(used: 720_000_000_000, total: nil)),
            (Remote(name: "Home NAS", type: "sftp", config: [:]), .unreachable(reason: "timeout"), nil),
        ]
    }

    static var cloudColors: [String: DesignSystem.Stratosphere.CloudColor] {
        DesignSystem.Stratosphere.CloudColors.assign(remotes.map { (name: $0.0.name, provider: $0.0.type) })
    }

    static var files: [FileItem] {
        let day: TimeInterval = 86_400
        func item(_ name: String, _ size: Int64, _ mime: String, dir: Bool = false, ago: Double) -> FileItem {
            FileItem(path: name, name: name, size: size, mimeType: mime, modTime: Date().addingTimeInterval(-ago * day),
                     isDir: dir, fileID: nil, qualifiedRemotePath: "Personal:\(name)")
        }
        return [
            item("Documents", 0, "inode/directory", dir: true, ago: 0.2),
            item("Photos", 0, "inode/directory", dir: true, ago: 1),
            item("Projects", 0, "inode/directory", dir: true, ago: 3),
            item("Budget 2026.xlsx", 840_000, "application/vnd.ms-excel", ago: 2),
            item("Deck.key", 48_000_000, "application/x-iwork-keynote-sffkey", ago: 5),
            item("Lease.pdf", 1_400_000, "application/pdf", ago: 12),
            item("Yosemite 2026.heic", 8_400_000, "image/heic", ago: 18),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: .constant(Optional(selection))) {
                SidebarToolLabel(title: "Home", systemImage: "house.fill",
                                 color: DesignSystem.Stratosphere.CloudColors.home)
                    .tag(SidebarSelection.home)
                Section {
                    ForEach(Self.remotes, id: \.0.name) { remote, status, quota in
                        SidebarRemoteRow(remote: remote, status: status, quota: quota,
                                         onEdit: {}, onDelete: {}, onReconnect: {})
                            .tag(SidebarSelection.remote(remote.name))
                    }
                } header: {
                    HStack {
                        Text("Clouds")
                        Spacer()
                        Image(systemName: "plus").foregroundStyle(.secondary)
                    }
                }
                Section("Tools") {
                    SidebarToolLabel(title: "Backups", systemImage: "clock.arrow.circlepath",
                                     color: DesignSystem.Stratosphere.CloudColors.backups)
                        .tag(SidebarSelection.backups)
                    SidebarToolLabel(title: "Copy Between Clouds", systemImage: "arrow.left.arrow.right",
                                     color: DesignSystem.Stratosphere.CloudColors.copy)
                        .tag(SidebarSelection.copySync)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStorageSummary(
                    totals: StorageTotals(quotas: Self.remotes.compactMap(\.2)),
                    clouds: Self.remotes.compactMap { remote, _, quota in
                        quota.map { (name: remote.name, quota: $0, color: Self.cloudColors[remote.name]) }
                    }
                )
                .padding(DesignSystem.Spacing.s)
            }
            .padding(.top, 38)
            .frame(width: 228)
            // Stands in for the system's floating sidebar.
            .glassSurface()
            .padding(10)

            VStack(spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.m) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                    Spacer()
                    Button("Copy Between Clouds…") {}
                    Button {} label: { Label("Add Cloud", systemImage: "plus") }
                }
                .buttonStyle(.glassCapsule)
                .padding(.horizontal, DesignSystem.Spacing.l)
                .frame(height: 52)
                content()
            }
        }
        .background { StratosphereBackdrop() }
        .environment(\.cloudColors, Self.cloudColors)
        .preferredColorScheme(.dark)
        .environment(FileProviderBridge())
        .environment(AppSettings(defaults: UserDefaults(suiteName: "DemoWindowPreview")!))
        .environment(RcloneDaemon())
        .environment(TransferStore())
        .environment(CloudMonitor(loadRemotes: { [] }, status: RemoteStatusService(client: RcloneDaemon().client)))
    }
}

#Preview("Window: Files", traits: .fixedLayout(width: 1280, height: 800)) {
    @Previewable @State var tab: VolumeTab = .files
    @Previewable @State var sortField: SortField = .name
    @Previewable @State var sortAscending = true
    let remote = Remote(name: "Personal", type: "drive", config: [:])
    let quota = StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000)
    let files = DemoWindow<EmptyView>.files
    DemoWindow(title: "Personal", selection: .remote("Personal")) {
        VolumePaneLayout {
            VolumeHeader(remote: remote, providerName: "Google Drive", quota: quota, status: .connected,
                         isInFinder: true, onPrimary: {}, onSync: {}, onEdit: {})
            VolumeTabBar(selection: $tab)
            VStack(spacing: 0) {
                FileTableHeader(sortField: $sortField, sortAscending: $sortAscending)
                Divider()
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        // Stands in for the AppKit table's inset selection.
                        FileRowView(file: file, remote: "Personal", isSelected: file.name == "Lease.pdf")
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(file.name == "Lease.pdf" ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
                            )
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.top, DesignSystem.Spacing.xs)
                Spacer(minLength: 0)
            }
            .glassContentSurface()
        }
    }
}

#Preview("Window: Finder tab", traits: .fixedLayout(width: 1280, height: 800)) {
    @Previewable @State var tab: VolumeTab = .finder
    let remote = Remote(name: "Personal", type: "drive", config: [:])
    let quota = StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000)
    let inFinder = MountConfig(remote: "Personal:", mountPoint: "", vfsMode: .readWrite, autoMount: true, backend: .fileProvider)
    let asVolume = MountConfig(remote: "Personal:", mountPoint: "/Volumes/Personal", vfsMode: .readWrite, autoMount: false, backend: .nfs)
    DemoWindow(title: "Personal", selection: .remote("Personal")) {
        VolumePaneLayout {
            VolumeHeader(remote: remote, providerName: "Google Drive", quota: quota, status: .connected,
                         isInFinder: true, onPrimary: {}, onSync: {}, onEdit: {})
            VolumeTabBar(selection: $tab)
            List {
                MountRow(config: inFinder, state: .on, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}, inCloudPane: true)
                MountRow(config: asVolume, state: .off, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}, inCloudPane: true)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .glassContentSurface()
        }
    }
}
#endif
