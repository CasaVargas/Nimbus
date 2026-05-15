import SwiftUI

extension DesignSystem {
    public enum Typography {
        public static let largeTitle      = Font.largeTitle
        public static let title            = Font.title
        public static let titleEmphasized  = Font.title.bold()
        public static let headline         = Font.headline
        public static let body             = Font.body
        public static let bodyEmphasized   = Font.body.bold()
        public static let callout          = Font.callout
        public static let caption          = Font.caption
        public static let captionEmphasized = Font.caption.bold()
        public static let caption2        = Font.caption2
        public static let footnote         = Font.footnote
    }
}
