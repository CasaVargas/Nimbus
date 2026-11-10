import SwiftUI

/// A glass surface. Pass a cloud's colour to wash the surface in it (page
/// headers, From/To wells).
///
/// On macOS 26 and later this is the system's Liquid Glass. On macOS 15 it
/// is drawn by hand: the backdrop through a blur, under a faint vertical
/// gradient and a hairline edge. Under Reduce Transparency it is one opaque
/// fill on every version; under Increase Contrast the drawn edge is stronger.
///
/// Never use this inside anything snapshot-tested: neither the blur nor
/// Liquid Glass renders the same on every machine.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var tint: DesignSystem.Stratosphere.CloudColor?

    @Environment(\.stratosphere) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            // Liquid Glass: the system's own material, which refracts what
            // is behind it and keeps its content legible on its own.
            content.glassEffect(liquidGlass, in: shape)
        } else {
            drawn(content, in: shape)
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlass: Glass {
        guard let tint else { return .regular }
        return .regular.tint(tint.start.color.opacity(0.35))
    }

    /// The same surface drawn by hand, for macOS 15 and for Reduce
    /// Transparency.
    private func drawn(_ content: Content, in shape: RoundedRectangle) -> some View {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(palette.opaqueSurface.color)
                    } else {
                        if colorScheme == .dark {
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
                .shadow(color: palette.glassShadow.color, radius: 16, y: 10)
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
        tint: DesignSystem.Stratosphere.CloudColor? = nil
    ) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint))
    }
}

/// Groups the glass surfaces of one screen so the system renders them
/// together, which Apple recommends when several are on screen at once.
/// Spacing is zero: neighbouring cards must stay separate shapes, not melt
/// into each other. Does nothing before macOS 26.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0, content: content)
        } else {
            content()
        }
    }
}
