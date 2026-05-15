import SwiftUI
import AppKit
import os

extension DesignSystem {
    public enum Lints {
        private static let logger = Logger(subsystem: "app.casavargas.nimbus", category: "lints")

        /// Runs at app startup in DEBUG. Asserts core semantic tokens resolve cleanly.
        @MainActor
        public static func runStartupChecks() {
            #if DEBUG
            let accent = NSColor(DesignSystem.Color.semantic.accent).cgColor
            assert(accent.alpha > 0, "accent color resolved to fully transparent")

            let surface = NSColor(DesignSystem.Color.semantic.surface).cgColor
            assert(surface.alpha > 0, "surface color resolved to fully transparent")

            logger.debug("DesignSystem.Lints.runStartupChecks OK")
            #endif
        }
    }
}
