import Foundation
import Security

/// HTTP Basic credentials for the rclone RC server.
///
/// Nimbus launches `rclone rcd` with a fresh random pair every time and
/// hands it to rclone through the environment (`RCLONE_RC_USER` /
/// `RCLONE_RC_PASS`), never argv, which every local user can read with
/// `ps`. Without credentials, any local process — or a web page making a
/// CORS "simple" request — could call `config/dump` and read every secret.
public struct RCCredentials: Sendable, Equatable {
    public let user: String
    public let password: String

    public init(user: String, password: String) {
        self.user = user
        self.password = password
    }

    /// 256 random bits for the password, base64url so it survives env vars
    /// and JSON untouched.
    public static func random() -> RCCredentials {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let password = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return RCCredentials(user: "nimbus", password: password)
    }

    /// The environment variables `rclone rcd` reads these from.
    public var environment: [String: String] {
        ["RCLONE_RC_USER": user, "RCLONE_RC_PASS": password]
    }

    var authorizationHeader: String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}
