import SwiftUI

/// Inline detail pane shown under the selected `MountRow`.
/// Reference: Disk Utility's right-hand inspector pane.
struct MountInspector: View {
    let config: MountConfig
    let lastMountedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            detail(
                label: "Mount Point",
                value: config.mountPoint.isEmpty ? "Finder (CloudStorage)" : config.mountPoint
            )
            detail(label: "Remote", value: config.remote)
            detail(label: "Backend", value: config.backend.displayName)
            detail(label: "VFS Mode", value: config.vfsMode.displayName)
            detail(label: "Mount at Launch", value: config.autoMount ? "On" : "Off")
            if let date = lastMountedAt {
                detail(label: "Last Mounted", value: Self.formatter.string(from: date))
            }
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .padding(.leading, DesignSystem.Spacing.l)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private func detail(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.m) {
            Text(verbatim: label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 100, alignment: .trailing)
            Text(verbatim: value)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

#Preview("MountInspector") {
    MountInspector(
        config: MountConfig(
            remote: "gdrive:",
            mountPoint: "/Users/me/Cloud/gdrive",
            vfsMode: .readWrite,
            autoMount: true,
            backend: .nfs
        ),
        lastMountedAt: Date()
    )
    .frame(width: 600)
    .padding()
}
