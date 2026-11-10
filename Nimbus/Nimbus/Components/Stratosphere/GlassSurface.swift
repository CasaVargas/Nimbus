import SwiftUI

/// A glass surface: the backdrop shows through a blur, under a faint
/// vertical gradient and a hairline edge. Pass a cloud's colour to wash the
/// surface in it (page headers, From/To wells).
///
/// Under Reduce Transparency the blur and gradient become one opaque fill;
/// under Increase Contrast the edge gets stronger.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var tint: DesignSystem.Stratosphere.CloudColor?
    /// False for surfaces that sit on an opaque background (a sheet, the
    /// Settings window): nothing shows through, so the blur and shadow only
    /// cost rendering and make snapshots differ between machines.
    var isTranslucent = true

    @Environment(\.stratosphere) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(palette.opaqueSurface.color)
                    } else {
                        if colorScheme == .dark, isTranslucent {
                            shape.fill(.ultraThinMaterial)
                        }
                        shape.fill(LinearGradient(
                            colors: [palette.glassTop.color, palette.glassBottom.color],
                            startPoint: .top, endPoint: .bottom
                        ))
                    }
                    if let tint {
                        shape.fill(LinearGradient(
                            colors: [tint.start.withAlpha(0.42).color, tint.end.withAlpha(0.10).color],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    }
                }
                .shadow(color: palette.glassShadow.color.opacity(isTranslucent ? 1 : 0), radius: 16, y: 10)
            }
            .overlay {
                shape.strokeBorder(
                    palette.glassBorder.color.opacity(contrast == .increased ? 2.5 : 1),
                    lineWidth: 1
                )
            }
    }
}

extension View {
    /// Puts the view on a Stratosphere glass surface.
    func glassSurface(
        radius: CGFloat = DesignSystem.Stratosphere.Radius.card,
        tint: DesignSystem.Stratosphere.CloudColor? = nil,
        isTranslucent: Bool = true
    ) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint, isTranslucent: isTranslucent))
    }
}
