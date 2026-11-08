import SwiftUI

/// A short, labelled progress strip for a guided flow ("Choose a service ›
/// Name it › Sign in"). Steps up to and including `current` are filled.
struct SetupSteps: View {
    let titles: [String]
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(index <= current ? DesignSystem.Color.semantic.accent
                                               : DesignSystem.Color.semantic.separator.opacity(0.7))
                        .frame(height: 3)
                    Text(verbatim: "\(index + 1). \(title)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(index == current ? DesignSystem.Color.semantic.textPrimary
                                                          : DesignSystem.Color.semantic.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Step \(current + 1) of \(titles.count), \(titles[min(current, titles.count - 1)])"))
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
