import Foundation
import os.log

private let sharedStateLogger = Logger(subsystem: "com.streamcloned.app.FileProvider", category: "shared-state")

/// Reads shared configuration from the App Group container.
/// The main Tauri app writes a JSON file with rclone port and remote config.
/// The File Provider extension reads it to connect to the daemon.
class SharedState {

    static let appGroupIdentifier = "group.com.streamcloned.app"
    static let stateFileName = "fileprovider-state.json"

    /// Port the rclone RC daemon is listening on, or nil if not running
    var rclonePort: UInt16? {
        guard let state = readState() else { return nil }
        return state["rclonePort"] as? UInt16
            ?? (state["rclonePort"] as? Int).flatMap({ UInt16(exactly: $0) })
    }

    /// List of configured remote names
    var configuredRemotes: [String] {
        guard let state = readState() else { return [] }
        return state["remotes"] as? [String] ?? []
    }

    /// Write state from the main app
    static func writeState(rclonePort: UInt16, remotes: [String]) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            sharedStateLogger.error("Failed to get App Group container URL")
            return
        }

        let stateURL = containerURL.appendingPathComponent(stateFileName)
        let state: [String: Any] = [
            "rclonePort": Int(rclonePort),
            "remotes": remotes,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: .prettyPrinted)
            try data.write(to: stateURL, options: .atomic)
            sharedStateLogger.info("Wrote File Provider shared state: port=\(rclonePort), remotes=\(remotes)")
        } catch {
            sharedStateLogger.error("Failed to write shared state: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func readState() -> [String: Any]? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedState.appGroupIdentifier
        ) else {
            sharedStateLogger.error("Failed to get App Group container URL")
            return nil
        }

        let stateURL = containerURL.appendingPathComponent(SharedState.stateFileName)
        guard let data = try? Data(contentsOf: stateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }
}
