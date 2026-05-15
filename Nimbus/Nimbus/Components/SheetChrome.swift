import SwiftUI

/// Standard sheet layout shared across all Nimbus modal sheets.
///
/// Layout (top to bottom):
/// - Header: title (Typography.titleEmphasized) + optional subtitle (caption, textSecondary)
/// - Body: scrollable region with consistent padding (Spacing.xl)
/// - Action bar: right-aligned button row, separator above
///
/// Sheet corner radius from DesignSystem.Radius.sheet (14pt).
/// Minimum width 460pt; height grows to body content.
struct SheetChrome<BodyContent: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let bodyContent: () -> BodyContent
    @ViewBuilder let actions: () -> Actions

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey?,
        @ViewBuilder body: @escaping () -> BodyContent,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.bodyContent = body
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                bodyContent()
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 460)
        .background(DesignSystem.Color.semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sheet, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Typography.titleEmphasized)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.l)
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            actions()
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.m)
    }
}
