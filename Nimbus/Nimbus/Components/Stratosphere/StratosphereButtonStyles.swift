import SwiftUI

/// The one filled, glowing control on a screen. A screen has at most one.
struct PrimaryPillButtonStyle: ButtonStyle {
    enum Size {
        case large, small

        var height: CGFloat { self == .large ? 46 : 32 }
        var padding: CGFloat { self == .large ? 26 : 16 }
        var font: Font {
            self == .large ? DesignSystem.Stratosphere.Typography.action
                           : DesignSystem.Stratosphere.Typography.actionSmall
        }
    }

    var size: Size = .large

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, size: size)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let size: Size
        @Environment(\.stratosphere) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(palette.onAction.color)
                .lineLimit(1)
                // A button's label is never worth truncating.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, size.padding)
                .frame(height: size.height)
                .background {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [palette.actionTop.color, palette.actionBottom.color],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .shadow(
                            color: palette.actionGlow.color.opacity(isEnabled ? 1 : 0),
                            radius: size == .large ? 14 : 8, y: size == .large ? 8 : 5
                        )
                }
                .overlay {
                    // Top highlight: the edge a lit capsule would catch.
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0)],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
                }
                .brightness(configuration.isPressed ? -0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(DesignSystem.Motion.snappy, value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}

/// Every other button: a quiet glass capsule.
struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration)
    }

    private struct CapsuleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.stratosphere) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(DesignSystem.Stratosphere.Typography.control)
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
                // A button's label is never worth truncating.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .frame(minWidth: 32, minHeight: 32)
                .glassSurface(radius: 16)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
        }
    }
}

extension ButtonStyle where Self == PrimaryPillButtonStyle {
    static var primaryPill: PrimaryPillButtonStyle { .init() }
    static func primaryPill(_ size: PrimaryPillButtonStyle.Size) -> PrimaryPillButtonStyle { .init(size: size) }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { .init() }
}
