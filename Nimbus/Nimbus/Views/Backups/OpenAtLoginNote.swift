import SwiftUI

/// The nudge that scheduled backups only run while Nimbus is open, with the
/// Open at Login toggle. Shared by the editor and the Backups screen footer.
enum OpenAtLoginNote {
    static let text = "Scheduled backups run while Nimbus is open, including from the menu bar."

    /// True while any of the schedules runs on its own and Open at Login is off.
    static func isShown(schedules: [BackupSchedule], openAtLoginIsOn: Bool) -> Bool {
        !openAtLoginIsOn && schedules.contains { $0 != .manual }
    }
}

struct OpenAtLoginNoteView: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            Text(verbatim: OpenAtLoginNote.text)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Open at Login", isOn: $isOn)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LaunchAtLoginService {
    /// A toggle binding that registers or unregisters the login item.
    var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { on in
                if on { self.register() } else { Task { await self.unregister() } }
            }
        )
    }
}
