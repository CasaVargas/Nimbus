import SwiftUI

/// One row in the Import Config preview list. Shows the parsed remote with a
/// checkbox, type pill, and an inline rename field only when both selected
/// and in conflict with an existing remote name.
struct ImportRemoteRow: View {
    let remote: ParsedRemote
    let isSelected: Bool
    let isConflict: Bool
    @Binding var rename: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text(verbatim: remote.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                    typePill
                    if isConflict {
                        Label("Name conflict", systemImage: "exclamationmark.triangle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
                    }
                }

                if isConflict && isSelected {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        Text("Rename to:")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        TextField("New name", text: $rename)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignSystem.Typography.caption)
                            .frame(maxWidth: 200)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, DesignSystem.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private var typePill: some View {
        Text(verbatim: remote.type)
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, DesignSystem.Spacing.xs + 2)
            .padding(.vertical, 2)
            .background(
                DesignSystem.Color.semantic.textSecondary.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
    }
}
