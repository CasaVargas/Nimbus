import SwiftUI
import RcloneKit

/// One remote in the sidebar's REMOTES section. Icon + name + a small status
/// dot (the full status pill is too heavy for a sidebar row). Right-click
/// exposes the same actions the old list row had.
struct SidebarRemoteRow: View {
    let remote: Remote
    let status: RemoteStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            ProviderIcon(provider: remote.type, size: 18)
                .frame(width: 20)

            Text(remote.name)
                .font(DesignSystem.Typography.body)
                .lineLimit(1)

            Spacer(minLength: DesignSystem.Spacing.s)

            Circle()
                .fill(status.tintColor)
                .frame(width: 7, height: 7)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            if case .authNeeded = status {
                Button("Reconnect", action: onReconnect)
            }
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remote.name), \(status.accessibilityLabel)")
        .accessibilityActions {
            Button("Edit", action: onEdit)
            if case .authNeeded = status {
                Button("Reconnect", action: onReconnect)
            }
            Button("Delete", action: onDelete)
        }
    }
}

#Preview {
    List {
        Section("Remotes") {
            SidebarRemoteRow(remote: Remote(name: "gdrive", type: "drive", config: [:]),
                             status: .connected, onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "backup-s3", type: "s3", config: [:]),
                             status: .authNeeded, onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "archive", type: "b2", config: [:]),
                             status: .unknown, onEdit: {}, onDelete: {}, onReconnect: {})
        }
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 200)
}
