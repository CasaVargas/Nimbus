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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DesignSystem.Spacing.s) {
                ProviderIcon(provider: iconType ?? remote.type, size: 18)
                    .frame(width: 20)

                Text(remote.name)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)

                Spacer(minLength: DesignSystem.Spacing.s)

                Circle()
                    .fill(status.tintColor)
                    .frame(width: 7, height: 7)
            }
            if let fraction = quota?.fraction {
                CapacityBar(fraction: fraction, isNearlyFull: quota?.isNearlyFull ?? false)
                    .padding(.leading, 28)
                    .padding(.trailing, 15)
            }
        }
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

/// The 3 pt capacity strip under a volume row. Accent while there is room,
/// warning tint from 90% so a nearly full drive is visible without opening it.
struct CapacityBar: View {
    let fraction: Double
    let isNearlyFull: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DesignSystem.Color.semantic.separator.opacity(0.6))
                Capsule()
                    .fill(isNearlyFull ? DesignSystem.Color.semantic.statusWarning : DesignSystem.Color.semantic.accent)
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent full")
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
