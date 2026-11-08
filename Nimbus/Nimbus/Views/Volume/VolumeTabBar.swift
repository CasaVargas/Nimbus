import SwiftUI

/// Underline tabs for the volume pane. Reference: the tab strip in Xcode's
/// project editor and Disk Utility's First Aid / Partition / Erase row:
/// text only, selected tab in primary weight with a 2 pt accent underline.
struct VolumeTabBar: View {
    @Binding var selection: VolumeTab

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(VolumeTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(DesignSystem.Motion.snappy) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected
                                         ? DesignSystem.Color.semantic.textPrimary
                                         : DesignSystem.Color.semantic.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.m)
                        .padding(.vertical, DesignSystem.Spacing.s)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? DesignSystem.Color.semantic.accent : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.top, DesignSystem.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloud sections")
    }
}

#Preview {
    @Previewable @State var tab: VolumeTab = .files
    VolumeTabBar(selection: $tab).frame(width: 500)
}
