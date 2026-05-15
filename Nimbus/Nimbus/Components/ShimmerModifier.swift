import SwiftUI

extension View {
    /// Applies a Mail-style shimmering highlight for loading placeholders.
    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    LinearGradient(
                        colors: [
                            .clear,
                            DesignSystem.Color.semantic.surface.opacity(0.6),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase * 200)
                    .mask(content)
                    .allowsHitTesting(false)
                    .task {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
    }
}
