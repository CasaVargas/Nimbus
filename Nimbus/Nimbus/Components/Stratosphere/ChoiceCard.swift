import SwiftUI

/// One answer to a question, as a card: a radio mark, a title and a
/// sentence. Use a short stack of these where a plain picker would hide
/// what each answer means.
struct ChoiceCard: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.stratosphere) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.m) {
                radio
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(DesignSystem.Stratosphere.Typography.sectionTitle)
                        .foregroundStyle(palette.textPrimary.color)
                    if let detail {
                        Text(verbatim: detail)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(palette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background {
                shape.fill(isSelected ? palette.actionTop.color.opacity(0.26) : palette.glassBottom.color)
            }
            .overlay {
                shape.strokeBorder(isSelected ? palette.actionTop.color : palette.glassBorder.color,
                                   lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var radio: some View {
        Circle()
            .strokeBorder(isSelected ? palette.actionTop.color : palette.textTertiary.color,
                          lineWidth: isSelected ? 6 : 2)
            .background(Circle().fill(isSelected ? Color.white : Color.clear))
            .frame(width: 18, height: 18)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 12) {
        ChoiceCard(title: "My Drive", detail: "The files in your own Google account.", isSelected: true, onSelect: {})
        ChoiceCard(title: "A shared drive", detail: "A team space your organization owns. You pick which one next.",
                   isSelected: false, onSelect: {})
    }
    .padding()
    .frame(width: 460)
    .background(DesignSystem.Stratosphere.Palette.dark.sheetTop.color)
    .preferredColorScheme(.dark)
}
