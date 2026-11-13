import Foundation

/// What the File Provider extension needs to reach the app's rclone daemon,
/// as written to `shared-state.json` by the app and read by the extension.
/// One type owns the keys so the two sides can't drift.
struct DaemonConnectionState: Equatable, Sendable {
    var port: Int
    /// The daemon's per-launch RC credentials. Nil only for state written by
    /// a Nimbus older than 1.2.2, whose daemon ran without authentication.
    var rcUser: String?
    var rcPassword: String?
    var remotes: [String] = []

    static let portKey = "rclonePort"
    static let userKey = "rcUser"
    static let passwordKey = "rcPass"
    static let remotesKey = "remotes"

    func encoded(updatedAt: Date = Date()) throws -> Data {
        var state: [String: Any] = [
            Self.portKey: port,
            Self.remotesKey: remotes,
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
        if let rcUser, let rcPassword {
            state[Self.userKey] = rcUser
            state[Self.passwordKey] = rcPassword
        }
        return try JSONSerialization.data(withJSONObject: state)
    }

    init(port: Int, rcUser: String? = nil, rcPassword: String? = nil, remotes: [String] = []) {
        self.port = port
        self.rcUser = rcUser
        self.rcPassword = rcPassword
        self.remotes = remotes
    }

    init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json[Self.portKey] as? Int, port > 0 else { return nil }
        self.port = port
        rcUser = json[Self.userKey] as? String
        rcPassword = json[Self.passwordKey] as? String
        remotes = json[Self.remotesKey] as? [String] ?? []
    }
}
