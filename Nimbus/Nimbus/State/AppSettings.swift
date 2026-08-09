import SwiftUI

enum Appearance: String, CaseIterable {
    case light, dark, system
}

@Observable
final class AppSettings {
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    init() {
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
    }

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
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    var sidebarCollapsed: Bool {
        get { defaults.bool(forKey: "sidebarCollapsed") }
        set { defaults.set(newValue, forKey: "sidebarCollapsed") }
    }

    /// Remotes whose File Provider domain the user explicitly turned off.
    /// The launch-time domain sync registers a domain for every rclone
    /// remote EXCEPT these — without this set, toggling a domain off in
    /// Mounts would silently come back on next launch.
    var disabledFileProviderDomains: Set<String> {
        get { Set(defaults.stringArray(forKey: "disabledFileProviderDomains") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "disabledFileProviderDomains") }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
