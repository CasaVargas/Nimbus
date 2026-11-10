import SwiftUI

extension DesignSystem {
    /// The Stratosphere visual language: a coloured backdrop, glass surfaces
    /// on it, one primary action per screen and a colour per cloud. See
    /// `docs/superpowers/specs/2026-11-09-stratosphere-redesign-design.md`.
    public enum Stratosphere {}
}

extension DesignSystem.Stratosphere {
    /// A colour kept as plain sRGB numbers so contrast can be checked in
    /// tests without resolving a `SwiftUI.Color` against a live environment.
    public struct RGBA: Hashable, Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
        public let a: Double

        public init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }

        public init(hex: UInt32, alpha: Double = 1) {
            self.init(
                r: Double((hex >> 16) & 0xFF) / 255,
                g: Double((hex >> 8) & 0xFF) / 255,
                b: Double(hex & 0xFF) / 255,
                a: alpha
            )
        }

        public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

        public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

        /// This colour drawn over an opaque one, the way the compositor
        /// blends it (in sRGB space, not linear light).
        public func over(_ background: RGBA) -> RGBA {
            RGBA(
                r: r * a + background.r * (1 - a),
                g: g * a + background.g * (1 - a),
                b: b * a + background.b * (1 - a),
                a: 1
            )
        }

        /// WCAG relative luminance of an opaque colour.
        public var luminance: Double {
            func linear(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        /// WCAG contrast ratio between two opaque colours, 1...21.
        public static func contrast(_ one: RGBA, _ two: RGBA) -> Double {
            let hi = max(one.luminance, two.luminance)
            let lo = min(one.luminance, two.luminance)
            return (hi + 0.05) / (lo + 0.05)
        }

        static func mix(_ from: RGBA, _ to: RGBA, _ t: Double) -> RGBA {
            RGBA(
                r: from.r + (to.r - from.r) * t,
                g: from.g + (to.g - from.g) * t,
                b: from.b + (to.b - from.b) * t,
                a: from.a + (to.a - from.a) * t
            )
        }
    }

    /// The window background as data: a linear base with soft elliptical
    /// glows on top. `StratosphereBackdrop` draws it and the contrast tests
    /// sample it, so the two can't drift apart.
    public struct Backdrop: Sendable {
        public struct Stop: Sendable {
            public let color: RGBA
            public let location: Double
        }

        /// A glow whose colour fades linearly to clear at `radius`. Position
        /// and radius are in unit coordinates of the window, so the glow is
        /// an ellipse that scales with it.
        public struct Glow: Sendable {
            public let x: Double
            public let y: Double
            public let radius: Double
            public let color: RGBA
        }

        public let base: [Stop]
        public let startX: Double, startY: Double
        public let endX: Double, endY: Double
        public let glows: [Glow]

        /// The composited colour at a unit point of the window.
        public func color(x: Double, y: Double) -> RGBA {
            let dx = endX - startX, dy = endY - startY
            let t = min(max(((x - startX) * dx + (y - startY) * dy) / (dx * dx + dy * dy), 0), 1)
            var result = base.last?.color ?? RGBA(hex: 0x000000)
            for (lower, upper) in zip(base, base.dropFirst()) where t <= upper.location {
                let span = upper.location - lower.location
                let local = span > 0 ? (t - lower.location) / span : 0
                result = RGBA.mix(lower.color, upper.color, min(max(local, 0), 1))
                break
            }
            for glow in glows {
                let distance = ((x - glow.x) * (x - glow.x) + (y - glow.y) * (y - glow.y)).squareRoot()
                let strength = max(0, 1 - distance / glow.radius)
                result = glow.color.withAlpha(glow.color.a * strength).over(result)
            }
            return result
        }
    }

    /// Every colour a Stratosphere view needs, for one appearance.
    public struct Palette: Sendable {
        public let backdrop: Backdrop

        public let textPrimary: RGBA
        public let textSecondary: RGBA
        public let textTertiary: RGBA

        /// Glass is a vertical gradient between these over a blur material.
        public let glassTop: RGBA
        public let glassBottom: RGBA
        public let glassBorder: RGBA
        /// What glass becomes under Reduce Transparency.
        public let opaqueSurface: RGBA
        public let glassShadow: RGBA
        /// Sheets and the menu bar panel: opaque, so they read as a layer
        /// above the window rather than another card in it.
        public let sheetTop: RGBA
        public let sheetBottom: RGBA

        public let track: RGBA
        public let selection: RGBA
        public let chipFill: RGBA
        public let rowSelection: RGBA

        public let actionTop: RGBA
        public let actionBottom: RGBA
        public let actionGlow: RGBA
        public let onAction: RGBA

        public let ok: RGBA
        public let warning: RGBA
        public let muted: RGBA
        public let error: RGBA

        public static func resolve(_ scheme: ColorScheme) -> Palette {
            scheme == .dark ? .dark : .light
        }
    }
}

// Short local names for the token tables below. Unqualified lookup inside an
// extension of a nested type doesn't reach its siblings.
private typealias Tone = DesignSystem.Stratosphere.RGBA
private typealias Sky = DesignSystem.Stratosphere.Backdrop

extension DesignSystem.Stratosphere.Palette {
    // Four values differ from the first mockups, because the contrast tests
    // failed with them: the blue glow is 0.50 (was 0.62), glass starts at
    // 0.10 (was 0.12), and secondary / tertiary text are 0.80 / 0.72 (were
    // 0.78 / 0.64). With the originals, tertiary text on glass near the
    // glow measured 3.4:1.
    public static let dark = DesignSystem.Stratosphere.Palette(
        backdrop: Sky(
            base: [
                .init(color: Tone(hex: 0x0B1640), location: 0),
                .init(color: Tone(hex: 0x0A1030), location: 0.45),
                .init(color: Tone(hex: 0x150C38), location: 1),
            ],
            startX: 0.3, startY: 0, endX: 0.7, endY: 1,
            glows: [
                .init(x: 0.80, y: -0.10, radius: 0.47, color: Tone(hex: 0x488CFF, alpha: 0.50)),
                .init(x: 0.06, y: 1.10, radius: 0.44, color: Tone(hex: 0x8854FF, alpha: 0.60)),
                .init(x: 1.00, y: 1.00, radius: 0.30, color: Tone(hex: 0xFF5CA8, alpha: 0.26)),
            ]
        ),
        textPrimary: Tone(hex: 0xFFFFFF),
        textSecondary: Tone(hex: 0xFFFFFF, alpha: 0.80),
        textTertiary: Tone(hex: 0xFFFFFF, alpha: 0.72),
        glassTop: Tone(hex: 0xFFFFFF, alpha: 0.10),
        glassBottom: Tone(hex: 0xFFFFFF, alpha: 0.05),
        glassBorder: Tone(hex: 0xFFFFFF, alpha: 0.16),
        opaqueSurface: Tone(hex: 0x16204F),
        glassShadow: Tone(hex: 0x000000, alpha: 0.18),
        sheetTop: Tone(hex: 0x2B3878),
        sheetBottom: Tone(hex: 0x181E4C),
        track: Tone(hex: 0xFFFFFF, alpha: 0.15),
        selection: Tone(hex: 0xFFFFFF, alpha: 0.17),
        chipFill: Tone(hex: 0xFFFFFF, alpha: 0.14),
        rowSelection: Tone(hex: 0x2459E0),
        actionTop: Tone(hex: 0x2B6CF0),
        actionBottom: Tone(hex: 0x1B48CC),
        actionGlow: Tone(hex: 0x3680FF, alpha: 0.6),
        onAction: Tone(hex: 0xFFFFFF),
        ok: Tone(hex: 0x45E3AA),
        warning: Tone(hex: 0xFFB84D),
        muted: Tone(hex: 0xA9B1C6),
        error: Tone(hex: 0xFF8080)
    )

    public static let light = DesignSystem.Stratosphere.Palette(
        backdrop: Sky(
            base: [
                .init(color: Tone(hex: 0xF7F9FD), location: 0),
                .init(color: Tone(hex: 0xEDF0F8), location: 1),
            ],
            startX: 0.5, startY: 0, endX: 0.5, endY: 1,
            glows: [
                .init(x: 0.86, y: -0.12, radius: 0.42, color: Tone(hex: 0x5498FF, alpha: 0.24)),
                .init(x: 0.00, y: 1.04, radius: 0.40, color: Tone(hex: 0x9670FF, alpha: 0.16)),
            ]
        ),
        textPrimary: Tone(hex: 0x14161C),
        textSecondary: Tone(hex: 0x14161C, alpha: 0.76),
        textTertiary: Tone(hex: 0x14161C, alpha: 0.64),
        glassTop: Tone(hex: 0xFFFFFF),
        glassBottom: Tone(hex: 0xFFFFFF),
        glassBorder: Tone(hex: 0x0C1846, alpha: 0.10),
        opaqueSurface: Tone(hex: 0xFFFFFF),
        glassShadow: Tone(hex: 0x182C6E, alpha: 0.09),
        sheetTop: Tone(hex: 0xFFFFFF),
        sheetBottom: Tone(hex: 0xF3F5FB),
        track: Tone(hex: 0x0C1846, alpha: 0.11),
        selection: Tone(hex: 0x2459E0, alpha: 0.13),
        chipFill: Tone(hex: 0x0C1846, alpha: 0.07),
        rowSelection: Tone(hex: 0x2459E0),
        actionTop: Tone(hex: 0x2B6CF0),
        actionBottom: Tone(hex: 0x1B48CC),
        actionGlow: Tone(hex: 0x3680FF, alpha: 0.4),
        onAction: Tone(hex: 0xFFFFFF),
        ok: Tone(hex: 0x0E9F6E),
        warning: Tone(hex: 0xC2710C),
        muted: Tone(hex: 0x6B7388),
        error: Tone(hex: 0xD92D20)
    )
}
