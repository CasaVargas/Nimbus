import SwiftUI

/// A short, labelled progress strip for a guided flow ("Choose a service ›
/// Name it › Sign in"): one capsule per step. The current step is filled;
/// finished steps read as done; later ones are quiet.
struct SetupSteps: View {
    let titles: [String]
    let current: Int

    @Environment(\.stratosphere) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(verbatim: "\(index + 1)  \(title)")
                    .font(DesignSystem.Stratosphere.Typography.segment)
                    .foregroundStyle(foreground(index))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, DesignSystem.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Capsule().fill(index == current ? palette.rowSelection.color : palette.glassBottom.color))
                    .overlay(Capsule().strokeBorder(index == current ? Color.clear : palette.glassBorder.color, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Step \(current + 1) of \(titles.count), \(titles[min(current, titles.count - 1)])"))
    }

    private func foreground(_ index: Int) -> Color {
        if index == current { return palette.onAction.color }
        return index < current ? palette.textPrimary.color : palette.textTertiary.color
    }
}

#Preview {
    VStack(spacing: 20) {
        SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 0)
        SetupSteps(titles: ["Choose a service", "Name it", "Set up"], current: 2)
    }
    .padding()
    .frame(width: 520)
}
