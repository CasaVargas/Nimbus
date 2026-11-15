import AppKit
import SwiftUI

extension DesignSystem {
    public enum Color {
        public enum semantic {
            public static let accent          = SwiftUI.Color.accentColor
            public static let surface         = SwiftUI.Color(nsColor: .windowBackgroundColor)
            public static let surfaceSubtle   = SwiftUI.Color(nsColor: .controlBackgroundColor)
            public static let surfaceElevated = SwiftUI.Color(nsColor: .underPageBackgroundColor)
            public static let selection       = SwiftUI.Color(nsColor: .selectedContentBackgroundColor)
            public static let separator       = SwiftUI.Color(nsColor: .separatorColor)
            // Text is the Stratosphere palette's, not the system labels'.
            // Every surface in the app is the theme's blue (or its light
            // counterpart), and the system's secondary and tertiary labels
            // (55% and 25% white in dark mode, tuned for a near-black
            // window) measure 3.7:1 and 1.9:1 on it. Small text needs
            // 4.5:1; the palette's 80% and 72% give 5.9:1 and 5.1:1.
            public static let textPrimary     = themed { $0.textPrimary }
            public static let textSecondary   = themed { $0.textSecondary }
            public static let textTertiary    = themed { $0.textTertiary }
            public static let statusOK        = SwiftUI.Color(nsColor: .systemGreen)
            public static let statusWarning   = SwiftUI.Color(nsColor: .systemOrange)
            public static let statusError     = SwiftUI.Color(nsColor: .systemRed)
            public static let statusInfo      = SwiftUI.Color(nsColor: .systemBlue)
            public static let statusMuted     = SwiftUI.Color(nsColor: .systemGray)

            /// A colour that follows the appearance of whatever draws it,
            /// taking its value from the Stratosphere palette.
            private static func themed(
                _ pick: @escaping @Sendable (DesignSystem.Stratosphere.Palette) -> DesignSystem.Stratosphere.RGBA
            ) -> SwiftUI.Color {
                SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let tone = pick(isDark ? .dark : .light)
                    return NSColor(srgbRed: tone.r, green: tone.g, blue: tone.b, alpha: tone.a)
                })
            }
        }
    }
}
