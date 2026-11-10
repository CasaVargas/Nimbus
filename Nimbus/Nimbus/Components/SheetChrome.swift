import SwiftUI

/// Standard sheet layout shared across all Nimbus modal sheets.
///
/// Layout (top to bottom):
/// - Header: title (Typography.titleEmphasized) + optional subtitle (caption, textSecondary)
/// - Body: scrollable region with consistent padding (Spacing.xl)
/// - Action bar: right-aligned button row, separator above
///
/// Stratosphere sheet surface: an opaque gradient, so a sheet reads as a
/// layer above the window. Minimum width 460pt; height grows to content.
struct SheetChrome<BodyContent: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let bodyContent: () -> BodyContent
    @ViewBuilder let actions: () -> Actions

    @Environment(\.stratosphere) private var palette

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
            if Actions.self != EmptyView.self {
                Divider()
                actionBar
            }
        }
        .frame(minWidth: 460)
        .environment(\.isOnStratosphereSheet, true)
        .background(LinearGradient(colors: [palette.sheetTop.color, palette.sheetBottom.color],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Stratosphere.Radius.sheet, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Stratosphere.Typography.sheetTitle)
                .foregroundStyle(palette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Stratosphere.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.l)
    }

    private var actionBar: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Spacer()
            actions()
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.m)
    }
}
