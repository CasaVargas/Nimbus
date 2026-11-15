import SwiftUI

extension DesignSystem.Stratosphere {
    /// The theme's text colours as a style, so a view can ask for them
    /// without reading the palette from the environment itself.
    ///
    /// Use these on Stratosphere surfaces instead of the system label
    /// colours. The system's secondary and tertiary labels are 55% and 25%
    /// white in dark mode, tuned for a near-black window; on the theme's
    /// blue they measure 3.7:1 and 1.9:1, well under the 4.5:1 that small
    /// text needs. The theme's own are 80% and 72% (5.9:1 and 5.1:1).
    struct TextStyle: ShapeStyle {
        enum Level: Sendable { case primary, secondary, tertiary }
        let level: Level

        func resolve(in environment: EnvironmentValues) -> SwiftUI.Color {
            let palette = environment.stratosphere
            return switch level {
            case .primary: palette.textPrimary.color
            case .secondary: palette.textSecondary.color
            case .tertiary: palette.textTertiary.color
            }
        }
    }
}

extension ShapeStyle where Self == DesignSystem.Stratosphere.TextStyle {
    /// The Stratosphere text colour for the current appearance.
    static func themeText(_ level: DesignSystem.Stratosphere.TextStyle.Level) -> Self {
        .init(level: level)
    }
}
