import SwiftUI

/// Warning callout for settings whose effect removes data (a mirror deletes
/// destination-only files; turning versions off makes that permanent).
struct DestructiveCallout: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
    }
}
