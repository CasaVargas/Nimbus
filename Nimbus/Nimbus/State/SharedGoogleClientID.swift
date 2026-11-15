import Foundation
import RcloneKit

/// rclone signs Google Drive in through its own shared client ID unless the
/// remote has one of its own. Google rate-limits that shared ID across every
/// rclone user (listings stall behind 403 `RATE_LIMIT_EXCEEDED` retries),
/// and rclone 1.76 warns it "will stop working during 2026".
enum SharedGoogleClientID {
    /// True for a Drive remote with no client ID and no service account.
    static func isUsed(type: String, config: [String: String]) -> Bool {
        func isSet(_ key: String) -> Bool {
            !(config[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return type == "drive"
            && !isSet("client_id")
            && !isSet("service_account_file")
            && !isSet("service_account_credentials")
    }

    static func isUsed(by remote: Remote) -> Bool {
        isUsed(type: remote.type, config: remote.config)
    }

    /// What every Google OAuth client ID ends in.
    static let clientIDSuffix = ".apps.googleusercontent.com"

    enum InputProblem: Equatable {
        case missingID, missingSecret, notAGoogleID

        var message: String {
            switch self {
            case .missingID: "Paste the client ID."
            case .missingSecret: "Paste the client secret."
            case .notAGoogleID: "That doesn't look like a Google client ID. It ends in \(clientIDSuffix)."
            }
        }
    }

    /// The trimmed pair, or what's wrong with it.
    static func validate(id: String, secret: String) -> Result<(id: String, secret: String), InputProblem> {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return .failure(.missingID) }
        if !id.hasSuffix(clientIDSuffix) || id.count == clientIDSuffix.count || id.contains(" ") {
            return .failure(.notAGoogleID)
        }
        if secret.isEmpty { return .failure(.missingSecret) }
        return .success((id, secret))
    }
}

extension SharedGoogleClientID.InputProblem: Error {}

extension SharedGoogleClientID {
    enum FileProblem: Error, Equatable {
        case unreadable, webClient

        var message: String {
            switch self {
            case .unreadable:
                "That isn't the file Google's Download JSON button gives you for an OAuth client."
            case .webClient:
                "That file is for a Web application client. Create one with application type Desktop app."
            }
        }
    }

    /// Reads the file Google's "Download JSON" gives for an OAuth client:
    /// `{"installed": {"client_id": "…", "client_secret": "…", …}}`. A
    /// "web" client is refused: its redirect addresses don't include the
    /// local one rclone signs in through.
    static func pair(fromDownloadedJSON data: Data) -> Result<(id: String, secret: String), FileProblem> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.unreadable)
        }
        guard let client = root["installed"] as? [String: Any] else {
            return .failure(root["web"] != nil ? .webClient : .unreadable)
        }
        guard let id = client["client_id"] as? String, let secret = client["client_secret"] as? String,
              case .success(let pair) = validate(id: id, secret: secret) else {
            return .failure(.unreadable)
        }
        return .success(pair)
    }
}
