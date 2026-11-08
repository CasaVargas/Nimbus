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

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
            ProviderBadge(provider: badgeType ?? remote.type, size: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(remote.name)
                    .font(DesignSystem.Typography.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignSystem.Spacing.l)

            HStack(spacing: DesignSystem.Spacing.s) {
                Button(isInFinder ? "Open in Finder" : "Show in Finder", action: onPrimary)
                    .buttonStyle(.borderedProminent)
                Button("Copy To…", action: onSync)
                    .buttonStyle(.bordered)
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.l)
    }

    private var subtitle: String {
        var parts: [String] = [providerName]
        if let quota, let used = quota.usedText {
            if let total = quota.totalText {
                parts.append("\(used) of \(total) used")
            } else {
                parts.append("\(used) used")
            }
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
    .frame(width: 760)
    .padding(.bottom)
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
    VStack(spacing: 0) {
        VolumeHeader(
            remote: remote,
            providerName: "Google Drive",
            quota: quota,
            status: .connected,
            isInFinder: true,
            onPrimary: {}, onSync: {}, onEdit: {}
        )
        StorageGauge(quota: quota)
        VolumeTabBar(selection: $tab)
        Divider()
        List {
            MountRow(config: inFinder, state: .on, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
            MountRow(config: asVolume, state: .off, onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
        }
        .listStyle(.inset)
    }
    .background(DesignSystem.Color.semantic.surface)
    .preferredColorScheme(.dark)
}
#endif
