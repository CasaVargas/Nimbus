import SwiftUI

enum Appearance: String, CaseIterable {
    case light, dark, system
}

@Observable
final class AppSettings {
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var rclonePort: Int {
        get { defaults.object(forKey: "rclonePort") as? Int ?? 5572 }
        set { defaults.set(newValue, forKey: "rclonePort") }
    }

    var rcloneBinaryPath: String {
        get { defaults.string(forKey: "rcloneBinaryPath") ?? Self.defaultRclonePath }
        set { defaults.set(newValue, forKey: "rcloneBinaryPath") }
    }

    private static let defaultRclonePath: String = {
        let candidates = [
            "/opt/homebrew/bin/rclone",
            "/usr/local/bin/rclone",
            "/usr/bin/rclone",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/local/bin/rclone"
    }()

    var bandwidthLimit: String {
        get { defaults.string(forKey: "bandwidthLimit") ?? "" }
        set { defaults.set(newValue, forKey: "bandwidthLimit") }
    }

    var concurrentTransfers: Int {
        get { defaults.object(forKey: "concurrentTransfers") as? Int ?? 4 }
        set { defaults.set(newValue, forKey: "concurrentTransfers") }
    }

    var onboardingComplete: Bool {
        get { defaults.bool(forKey: "onboardingComplete") }
        set { defaults.set(newValue, forKey: "onboardingComplete") }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }

    var sidebarCollapsed: Bool {
        get { defaults.bool(forKey: "sidebarCollapsed") }
        set { defaults.set(newValue, forKey: "sidebarCollapsed") }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
