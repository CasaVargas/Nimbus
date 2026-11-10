import SwiftUI

extension DesignSystem.Stratosphere {
    /// Corner radii for Stratosphere surfaces. Kept apart from
    /// `DesignSystem.Radius` until every screen has moved over, so screens
    /// that haven't been restyled yet don't change shape underneath.
    public enum Radius {
        public static let row: CGFloat = 10
        public static let card: CGFloat = 20
        public static let header: CGFloat = 24
        public static let sheet: CGFloat = 26
    }

    /// Display type. Rounded for headlines and titles only; body text stays
    /// on the system text styles. Fixed sizes live here and nowhere else:
    /// `scripts/lint-no-system-size.sh` rejects them in views.
    public enum Typography {
        public static let hero = Font.system(size: 52, weight: .heavy, design: .rounded)
        public static let pageTitle = Font.system(size: 30, weight: .heavy, design: .rounded)
        public static let sheetTitle = Font.system(size: 22, weight: .heavy, design: .rounded)
        public static let sectionTitle = Font.system(size: 15, weight: .bold, design: .rounded)
        public static let action = Font.system(size: 15, weight: .semibold, design: .rounded)
        public static let actionSmall = Font.system(size: 13, weight: .semibold, design: .rounded)
        public static let chip = Font.system(size: 11.5, weight: .semibold)
        /// The figure in the middle of the storage ring.
        public static let ringValue = Font.system(size: 40, weight: .heavy, design: .rounded)
        /// The sentence under a hero headline.
        public static let lead = Font.system(size: 14.5)
        public static let label = Font.body.weight(.semibold)
        public static let control = Font.body.weight(.medium)
        public static let detail = Font.callout
        public static let segment = Font.callout.weight(.semibold)
    }
}

extension EnvironmentValues {
    /// Each cloud's colour by remote name, assigned once for the window so
    /// the sidebar, Home and a cloud's own page agree.
    @Entry var cloudColors: [String: DesignSystem.Stratosphere.CloudColor] = [:]

    /// True inside `SheetChrome`. Lets shared pieces such as `FormSection`
    /// match the sheet while Settings, which also uses them, keeps its
    /// current look until it is restyled.
    @Entry var isOnStratosphereSheet = false

    /// The Stratosphere palette for the current appearance.
    var stratosphere: DesignSystem.Stratosphere.Palette {
        DesignSystem.Stratosphere.Palette.resolve(colorScheme)
    }
}
