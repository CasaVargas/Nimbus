import SwiftUI
import RcloneKit

/// One remote in the sidebar's REMOTES section. Icon + name + a small status
/// dot (the full status pill is too heavy for a sidebar row). Right-click
/// exposes the same actions the old list row had.
struct SidebarRemoteRow: View {
    let remote: Remote
    let status: RemoteStatus
    var quota: StorageQuota? = nil
    /// Backend type for the icon; an alias passes the type it points at.
    var iconType: String? = nil
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReconnect: () -> Void

    @Environment(\.cloudColors) private var cloudColors

    private var provider: String { iconType ?? remote.type }

    /// The cloud's own colour, or the warning colour from 90% so a nearly
    /// full drive is visible without opening it.
    private var barColor: DesignSystem.Stratosphere.CloudColor {
        if quota?.isNearlyFull ?? false { return DesignSystem.Stratosphere.CloudColors.nearlyFull }
        return cloudColors[remote.name] ?? DesignSystem.Stratosphere.CloudColors.color(forProvider: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DesignSystem.Spacing.s) {
                LogoTile(provider: provider, size: .small)

                Text(remote.name)
                    .font(DesignSystem.Stratosphere.Typography.control)
                    .lineLimit(1)

                Spacer(minLength: DesignSystem.Spacing.s)

                StatusDot(status: status.stratosphere)
            }
            if let fraction = quota?.fraction {
                UsageBar(fraction: fraction, color: barColor, height: 3)
                    .padding(.leading, 32)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            if case .authNeeded = status {
                Button("Check Again", action: onReconnect)
            }
            Divider()
            Button("Remove…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remote.name), \(status.accessibilityLabel)")
        .accessibilityActions {
            Button("Edit", action: onEdit)
            if case .authNeeded = status {
                Button("Check Again", action: onReconnect)
            }
            Button("Remove", action: onDelete)
        }
    }
}

#Preview {
    List {
        Section("Volumes") {
            SidebarRemoteRow(remote: Remote(name: "gdrive", type: "drive", config: [:]),
                             status: .connected,
                             quota: StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000),
                             onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "backup-s3", type: "s3", config: [:]),
                             status: .authNeeded, onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "archive", type: "b2", config: [:]),
                             status: .unknown, onEdit: {}, onDelete: {}, onReconnect: {})
        }
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 200)
}
