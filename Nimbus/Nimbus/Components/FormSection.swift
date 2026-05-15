import SwiftUI

/// Wraps a SwiftUI section of preference-form rows with consistent typography
/// and spacing. Matches macOS System Settings preference-form style.
///
/// Use FormRow for individual labeled rows inside the section.
struct FormSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            if let title {
                Text(title)
                    .font(DesignSystem.Typography.captionEmphasized)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(DesignSystem.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )
            if let footer {
                Text(footer)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
    }
}

/// A single labeled row inside a FormSection. Label on the left, trailing content
/// (e.g. TextField, Picker, value Text) on the right.
///
/// **Trailing-width contract:** the row's `Spacer()` consumes all flex between
/// label and trailing. Trailing content controls its own width. For TextFields
/// that should expand horizontally, apply `.frame(maxWidth: <number>)` (typically
/// 200–280pt for most form inputs). Don't add `.frame(maxWidth: .infinity)` —
/// the trailing area is bounded by row width, not infinite.
struct FormRow<Trailing: View>: View {
    let label: LocalizedStringKey
    let help: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.m) {
                Text(label)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Spacer()
                trailing()
            }
            if let help {
                Text(help)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
