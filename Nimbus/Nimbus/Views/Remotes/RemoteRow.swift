import SwiftUI
import RcloneKit

enum RemoteStatus: Equatable, Sendable {
    case unknown
    case connected
    case authNeeded
    case error(reason: String)

    var pillText: String {
        switch self {
        case .unknown: return "○ Checking…"
        case .connected: return "● Connected"
        case .authNeeded: return "⚠ Sign In"
        case .error: return "! Error"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown: return DesignSystem.Color.semantic.textSecondary
        case .connected: return DesignSystem.Color.semantic.statusOK
        case .authNeeded: return DesignSystem.Color.semantic.statusWarning
        case .error: return DesignSystem.Color.semantic.statusError
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown: return "Status checking"
        case .connected: return "Connected"
        case .authNeeded: return "Sign in required"
        case .error(let reason): return "Error: \(reason)"
        }
    }
}

/// Row representing a single remote in the Remotes list.
/// Reference: Disk Utility's volume row.
struct RemoteRow: View {
    let remote: Remote
    let status: RemoteStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBrowse: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: iconName(for: remote.type))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(remote.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(remote.type)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }

            Spacer()

            statusPill
                .accessibilityLabel(status.accessibilityLabel)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onBrowse() }
        .contextMenu {
            Button("Browse") { onBrowse() }
            Button("Edit") { onEdit() }
            if case .authNeeded = status {
                Button("Reconnect") { onReconnect() }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Browse") { onBrowse() }
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: "Reconnect") { onReconnect() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var statusPill: some View {
        Text(status.pillText)
            .font(DesignSystem.Typography.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                status.tintColor.opacity(0.18),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
            )
            .foregroundStyle(status.tintColor)
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "drive": return "externaldrive.connected.to.line.below"
        case "s3": return "shippingbox"
        case "dropbox": return "drop"
        case "onedrive": return "cloud"
        case "sftp", "ftp": return "server.rack"
        case "local": return "folder"
        case "crypt": return "lock.shield"
        default: return "cloud"
        }
    }
}
