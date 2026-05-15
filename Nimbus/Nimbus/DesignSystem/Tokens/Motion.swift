import SwiftUI

extension DesignSystem {
    public enum Motion {
        public static let snappyDuration:  Double = 0.18
        public static let smoothDuration:  Double = 0.22
        public static let springyDuration: Double = 0.25

        public static let snappy  = Animation.snappy(duration: snappyDuration)
        public static let smooth  = Animation.smooth(duration: smoothDuration)
        public static let springy = Animation.bouncy(duration: springyDuration)
    }
}
