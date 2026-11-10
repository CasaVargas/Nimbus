import SwiftUI

/// Warning callout for settings whose effect removes data (a mirror deletes
/// destination-only files; turning versions off makes that permanent).
struct DestructiveCallout: View {
    let message: LocalizedStringKey

    @Environment(\.stratosphere) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning.color)
                .accessibilityHidden(true)
            Text(message)
                .font(DesignSystem.Stratosphere.Typography.detail)
                .foregroundStyle(palette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.m)
        .background(shape.fill(palette.warning.color.opacity(0.18)))
        .overlay(shape.strokeBorder(palette.warning.color.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
