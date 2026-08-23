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
            public static let textPrimary     = SwiftUI.Color(nsColor: .labelColor)
            public static let textSecondary   = SwiftUI.Color(nsColor: .secondaryLabelColor)
            public static let textTertiary    = SwiftUI.Color(nsColor: .tertiaryLabelColor)
            public static let statusOK        = SwiftUI.Color(nsColor: .systemGreen)
            public static let statusWarning   = SwiftUI.Color(nsColor: .systemOrange)
            public static let statusError     = SwiftUI.Color(nsColor: .systemRed)
            public static let statusInfo      = SwiftUI.Color(nsColor: .systemBlue)
            public static let statusMuted     = SwiftUI.Color(nsColor: .systemGray)
        }
    }
}
