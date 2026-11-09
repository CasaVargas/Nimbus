import SwiftUI

/// A cloud's four tabs, as a glass segmented control.
struct VolumeTabBar: View {
    @Binding var selection: VolumeTab

    var body: some View {
        HStack {
            GlassSegmented(
                options: VolumeTab.allCases.map { .init(value: $0, title: $0.title) },
                selection: $selection
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloud sections")
    }
}

/// The spacing and margins of a cloud's page: header, tabs, content. One
/// place, so the live pane and the screenshot previews can't drift.
struct VolumePaneLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m, content: content)
            .padding(.horizontal, 20)
            .padding(.top, DesignSystem.Spacing.xs)
            .padding(.bottom, DesignSystem.Spacing.l)
    }
}

#Preview {
    @Previewable @State var tab: VolumeTab = .files
    VolumeTabBar(selection: $tab).padding().frame(width: 500).background { StratosphereBackdrop() }
}
