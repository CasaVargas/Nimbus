import SwiftUI

/// Wraps a group of preference-form rows. Same visual language as Home's
/// groups: a sentence-case heading, a subtle filled container with a hairline
/// edge, and a divider between adjacent rows.
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
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                    .padding(.leading, DesignSystem.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().padding(.vertical, DesignSystem.Spacing.xs)
                        }
                        row
                    }
                }
            }
            .padding(DesignSystem.Spacing.m)
            .glassSurface(radius: 16)
            if let footer {
                Text(footer)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .padding(.leading, DesignSystem.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
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
