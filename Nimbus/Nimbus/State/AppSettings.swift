import SwiftUI

enum Appearance: String, CaseIterable {
    case light, dark, system
}

/// App-wide preferences persisted to `UserDefaults.standard`.
///
/// Every persisted property is a *stored* `var` with a `didSet` that writes
/// through to `defaults`, initialized from `defaults` in `init`. This is
/// deliberate: the `@Observable` macro only instruments stored properties, so a
/// computed property backed by `@ObservationIgnored` `defaults` would read and
/// write correctly but emit **no** change notification — any SwiftUI view
/// observing it (or a `$settings.foo` binding) would silently fail to update.
/// (Property observers don't fire during `init`, so the initial reads below
/// don't redundantly write back.)
@Observable
final class AppSettings {
    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        rclonePort = defaults.object(forKey: "rclonePort") as? Int ?? 5572
        rcloneBinaryPath = defaults.string(forKey: "rcloneBinaryPath") ?? Self.defaultRclonePath
        bandwidthLimit = defaults.string(forKey: "bandwidthLimit") ?? ""
        concurrentTransfers = defaults.object(forKey: "concurrentTransfers") as? Int ?? 4
        sidebarCollapsed = defaults.bool(forKey: "sidebarCollapsed")
        disabledFileProviderDomains = Set(defaults.stringArray(forKey: "disabledFileProviderDomains") ?? [])
        addNewRemotesToFinder = defaults.object(forKey: "addNewRemotesToFinder") as? Bool ?? true
        newMountAccess = MountAccessDefault(rawValue: defaults.string(forKey: "newMountAccess") ?? "") ?? .readWrite
        newMountAutoMount = defaults.bool(forKey: "newMountAutoMount")
        defaultConflictPolicy = ConflictPolicy(rawValue: defaults.string(forKey: "defaultConflictPolicy") ?? "") ?? .rename
        transferNotificationMode = TransferNotificationMode(rawValue: defaults.string(forKey: "transferNotificationMode") ?? "") ?? .failuresOnly
        transferHistoryRetention = TransferHistoryRetention(rawValue: defaults.string(forKey: "transferHistoryRetention") ?? "") ?? .sevenDays
    }

    var rclonePort: Int {
        didSet { defaults.set(rclonePort, forKey: "rclonePort") }
    }

    var rcloneBinaryPath: String {
        didSet { defaults.set(rcloneBinaryPath, forKey: "rcloneBinaryPath") }
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
        didSet { defaults.set(bandwidthLimit, forKey: "bandwidthLimit") }
    }

    var concurrentTransfers: Int {
        didSet { defaults.set(concurrentTransfers, forKey: "concurrentTransfers") }
    }

    var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    var sidebarCollapsed: Bool {
        didSet { defaults.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }

    /// Remotes whose File Provider domain the user explicitly turned off.
    /// The launch-time domain sync registers a domain for every rclone
    /// remote EXCEPT these — without this set, toggling a domain off in
    /// Mounts would silently come back on next launch.
    var disabledFileProviderDomains: Set<String> {
        didSet {
            defaults.set(Array(disabledFileProviderDomains).sorted(), forKey: "disabledFileProviderDomains")
        }
    }

    var addNewRemotesToFinder: Bool {
        didSet { defaults.set(addNewRemotesToFinder, forKey: "addNewRemotesToFinder") }
    }

    var newMountAccess: MountAccessDefault {
        didSet { defaults.set(newMountAccess.rawValue, forKey: "newMountAccess") }
    }

    var newMountAutoMount: Bool {
        didSet { defaults.set(newMountAutoMount, forKey: "newMountAutoMount") }
    }

    var defaultConflictPolicy: ConflictPolicy {
        didSet { defaults.set(defaultConflictPolicy.rawValue, forKey: "defaultConflictPolicy") }
    }

    var transferNotificationMode: TransferNotificationMode {
        didSet { defaults.set(transferNotificationMode.rawValue, forKey: "transferNotificationMode") }
    }

    var transferHistoryRetention: TransferHistoryRetention {
        didSet { defaults.set(transferHistoryRetention.rawValue, forKey: "transferHistoryRetention") }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
