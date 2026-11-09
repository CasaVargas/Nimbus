import SwiftUI

/// The window background every Stratosphere screen sits on. Use one per
/// window, behind everything including the sidebar. It draws exactly what
/// `DesignSystem.Stratosphere.Backdrop` describes, which is also what the
/// contrast tests sample.
struct StratosphereBackdrop: View {
    @Environment(\.stratosphere) private var palette

    var body: some View {
        let backdrop = palette.backdrop
        ZStack {
            LinearGradient(
                stops: backdrop.base.map { .init(color: $0.color.color, location: $0.location) },
                startPoint: UnitPoint(x: backdrop.startX, y: backdrop.startY),
                endPoint: UnitPoint(x: backdrop.endX, y: backdrop.endY)
            )
            ForEach(Array(backdrop.glows.enumerated()), id: \.offset) { _, glow in
                EllipticalGradient(
                    // Fade to the same hue at zero alpha, not to `.clear`
                    // (transparent black), which would grey the falloff.
                    colors: [glow.color.color, glow.color.withAlpha(0).color],
                    center: UnitPoint(x: glow.x, y: glow.y),
                    startRadiusFraction: 0,
                    endRadiusFraction: glow.radius
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
