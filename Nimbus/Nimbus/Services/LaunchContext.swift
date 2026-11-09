import Foundation

/// How this process was launched. A copy of the app that Xcode starts only to
/// host unit tests or to render previews shares the machine with the real
/// app, so it must leave system-wide state alone: no `rclone rcd`, and no
/// ending of processes or mounts it did not start.
enum LaunchContext: Equatable, Sendable {
    /// A user launch, including a normal Debug run from Xcode.
    case normal
    /// The app is the host of an XCTest / Swift Testing bundle.
    case testHost
    /// The app is the host of an Xcode preview.
    case previewHost

    /// The context of the running process. Computed on every read because
    /// XCTest can be loaded into the process after launch.
    static var current: LaunchContext {
        detect(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: NSClassFromString("XCTestCase") != nil
        )
    }

    /// Pure detection, so every signal can be unit tested.
    static func detect(environment: [String: String], isXCTestLoaded: Bool) -> LaunchContext {
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .previewHost
        }
        let testKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        if isXCTestLoaded || testKeys.contains(where: { environment[$0] != nil }) {
            return .testHost
        }
        return .normal
    }

    /// Whether this process may start the rclone daemon and end stale rclone
    /// processes and mounts left by an earlier session.
    var managesSystemProcesses: Bool { self == .normal }
}
