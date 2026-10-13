import Foundation

/// One question rclone's interactive config machine is asking, plus the
/// opaque cursor to echo back when answering it.
public struct ConfigQuestion: Sendable, Equatable {
    public let option: ProviderOption
    public let state: String

    public init(option: ProviderOption, state: String) {
        self.option = option
        self.state = state
    }
}

/// A typed view of one turn of rclone's `config/create` state machine, so
/// callers never parse a state string themselves.
public enum ConfigStep: Sendable, Equatable {
    /// A plain option to render as a form field.
    case question(ConfigQuestion)
    /// An `*oauth-*` state: browser sign-in, not a text field.
    case oauth(ConfigQuestion)
    /// rclone's own `config_fs_advanced` gate — "edit advanced config?"
    case advancedGate(ConfigQuestion)
    /// Machine finished; the remote now exists in rclone.conf.
    case done
}

/// Raw shape of a `config/create` reply. `Result` is deliberately not
/// decoded — nothing in Nimbus reads it.
private struct ConfigMachineResponse: Decodable, Sendable {
    let error: String
    let option: ProviderOption?
    let state: String

    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case option = "Option"
        case state = "State"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = (try? c.decode(String.self, forKey: .error)) ?? ""
        option = try? c.decodeIfPresent(ProviderOption.self, forKey: .option)
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
    }
}

extension RcloneClient {

    /// Begins an interactive config walk.
    ///
    /// `askAll: false` asks only rclone's post-config questions. That is
    /// correct for OAuth backends (drive, dropbox, onedrive, box, pcloud),
    /// which jump straight to `*oauth-islocal`. It is WRONG for credential
    /// backends (s3, sftp, b2, webdav): they ask nothing at all and rclone
    /// writes a stub remote with no host and no credentials. Callers detect
    /// the difference by whether this returns `.oauth`.
    public func startConfig(
        name: String,
        type: String,
        askAll: Bool
    ) async throws -> ConfigStep {
        try await configCall(name: name, type: type, opt: [
            "nonInteractive": true,
            "all": askAll,
        ])
    }

    /// Answers the current question and returns the next step.
    ///
    /// Note there is no `config/continue` RC method — continuation is
    /// `config/create` again with the cursor carried inside `opt`.
    public func continueConfig(
        name: String,
        type: String,
        state: String,
        result: String,
        askAll: Bool
    ) async throws -> ConfigStep {
        try await configCall(name: name, type: type, opt: [
            "nonInteractive": true,
            "all": askAll,
            "continue": true,
            "state": state,
            "result": result,
        ])
    }

    /// Removes the partial remote `config/create` writes on its first call.
    /// Deliberately swallows errors: it runs on cancel and error paths where
    /// the remote may legitimately not exist yet.
    public func deletePartialRemote(name: String) async {
        try? await deleteRemote(name: name)
    }

    private func configCall(
        name: String,
        type: String,
        opt: [String: any Sendable]
    ) async throws -> ConfigStep {
        let response: ConfigMachineResponse = try await call("config/create", params: [
            "name": name,
            "type": type,
            "parameters": [String: String](),
            "opt": opt,
        ])

        // rclone reports config failures in the body of a 200, not the
        // status code. Checking only the status reports success on failure.
        guard response.error.isEmpty else {
            throw RcloneError.requestFailed(status: 200, message: response.error)
        }

        guard let option = response.option, !response.state.isEmpty else {
            return .done
        }
        let question = ConfigQuestion(option: option, state: response.state)
        if response.state.hasPrefix("*oauth") { return .oauth(question) }
        if option.name == "config_fs_advanced" { return .advancedGate(question) }
        return .question(question)
    }
}
