import SwiftUI

/// Row representing a single configured mount. Layout mirrors macOS System
/// Settings → Login Items: leading icon, two-line label, trailing switch.
/// Reference: macOS System Settings · Login Items, Disk Utility volume row.
struct MountRow: View {
    let config: MountConfig
    let state: StatusToggleState
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: icon(for: state))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(tint(for: state))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(verbatim: "\(config.remote)  ·  \(config.backend.displayName)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }

            Spacer()

            StatusToggle(state: state, onToggle: onToggle)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            if case .on = state {
                Button("Reveal in Finder") { onRevealInFinder() }
            }
            Button("Edit Mount") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var displayName: String {
        let leaf = (config.mountPoint as NSString).lastPathComponent
        return leaf.isEmpty ? "Mount" : leaf
    }

    private func icon(for state: StatusToggleState) -> String {
        switch state {
        case .on, .unmounting: return "externaldrive.fill"
        case .off, .mounting: return "externaldrive"
        case .error: return "externaldrive.badge.xmark"
        }
    }

    private func tint(for state: StatusToggleState) -> Color {
        switch state {
        case .on: return DesignSystem.Color.semantic.statusInfo
        case .error: return DesignSystem.Color.semantic.statusError
        default: return DesignSystem.Color.semantic.textTertiary
        }
    }
}

extension MountBackend {
    var displayName: String {
        switch self {
        case .nfs: return "NFS"
        case .fileProvider: return "File Provider"
        }
    }
}

extension VFSMode {
    var displayName: String {
        switch self {
        case .readOnly: return "Read-only"
        case .readWrite: return "Read-write"
        }
    }
}

#Preview("MountRow states") {
    let config = MountConfig(
        remote: "gdrive:",
        mountPoint: "/Users/me/Cloud/gdrive",
        vfsMode: .readWrite,
        autoMount: false,
        backend: .nfs
    )
    return VStack(spacing: 0) {
        MountRow(config: config, state: .off,
                 onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
        MountRow(config: config, state: .mounting,
                 onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
        MountRow(config: config, state: .on,
                 onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
        MountRow(config: config, state: .error(reason: "Permission denied"),
                 onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {})
    }
    .padding()
    .frame(width: 500)
}
