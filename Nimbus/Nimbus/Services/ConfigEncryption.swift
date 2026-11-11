import Foundation
import Security
import os

// Locks rclone.conf with rclone's own config encryption, using a random
// password kept in the login Keychain (#67). Spec:
// docs/superpowers/specs/2026-11-11-keychain-config-encryption-design.md

/// A short, blocking command run. Call off the main actor.
struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let error: String
    var succeeded: Bool { status == 0 }
}

enum Command {
    /// Runs `path args…`, optionally writing `input` to its stdin, and kills
    /// it after `timeout` so a misbehaving binary can't wedge the caller.
    static func run(
        _ path: String,
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe = input.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "", error: error.localizedDescription)
        }
        if let inPipe, let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        // Outputs here are a few lines, far below the pipe buffer, so reading
        // after exit cannot deadlock.
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            done.wait()
            return CommandResult(status: -1, output: "", error: "Timed out")
        }
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(status: process.terminationStatus, output: output, error: error)
    }
}

/// The rclone config password, as a generic-password item in the login
/// Keychain. `/usr/bin/security` creates the item, so `security` can read it
/// back without a Keychain prompt when rclone runs the password command. The
/// password itself goes to `security -i` over stdin, never on a command line.
struct KeychainConfigPassword: Sendable, Equatable {
    static let standard = KeychainConfigPassword(service: "app.casavargas.nimbus", account: "rclone-config")

    let service: String
    let account: String

    private static let security = "/usr/bin/security"

    /// What rclone runs to read the password. Also the line users export as
    /// `RCLONE_PASSWORD_COMMAND` to use the rclone command line.
    var passwordCommand: String {
        "\(Self.security) find-generic-password -s \(service) -a \(account) -w"
    }

    /// The shell line shown in Settings and the README.
    var exportLine: String {
        "export RCLONE_PASSWORD_COMMAND='\(passwordCommand)'"
    }

    /// Metadata lookup only: never reads the secret, never prompts.
    func exists() -> Bool {
        Command.run(Self.security, ["find-generic-password", "-s", service, "-a", account]).succeeded
    }

    /// Creates the item unless one exists. An existing item is reused, never
    /// overwritten: an older encrypted config or backup may still need it.
    /// Returns true when it created a new item.
    @discardableResult
    func createIfMissing() throws -> Bool {
        if exists() { return false }
        let password = try Self.randomPassword()
        let line = "add-generic-password -s \(service) -a \(account) -l \"Nimbus rclone config\" -w \"\(password)\"\n"
        let result = Command.run(Self.security, ["-i"], input: line)
        guard exists() else {
            throw ConfigEncryptionError.keychain(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return true
    }

    func delete() throws {
        guard exists() else { return }
        let result = Command.run(Self.security, ["delete-generic-password", "-s", service, "-a", account])
        guard result.succeeded else {
            throw ConfigEncryptionError.keychain(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 32 random bytes, base64: no spaces or quotes, so it is safe inside the
    /// quoted `security -i` argument.
    private static func randomPassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ConfigEncryptionError.keychain("Could not generate a password.")
        }
        return Data(bytes).base64EncodedString()
    }
}

enum ConfigEncryptionError: LocalizedError, Equatable {
    case keychain(String)
    case configNotFound
    case rclone(String)
    case notApplied

    var errorDescription: String? {
        switch self {
        case .keychain(let detail):
            detail.isEmpty ? "Keychain refused to save the password." : "Keychain: \(detail)"
        case .configNotFound:
            "Couldn't find rclone.conf."
        case .rclone(let detail):
            detail.isEmpty ? "rclone couldn't change rclone.conf." : detail
        case .notApplied:
            "rclone.conf didn't change. Nothing was lost; it's back as it was."
        }
    }
}

enum RcloneConfigFile {
    static let encryptedHeader = "# Encrypted rclone configuration File"

    static func isEncrypted(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: encryptedHeader.utf8.count)) ?? Data()
        return String(data: head, encoding: .utf8) == encryptedHeader
    }

    /// Asks rclone where its config lives (`rclone config file`), so Nimbus
    /// edits the same file the daemon reads, including `RCLONE_CONFIG`.
    static func locate(binaryPath: String) -> URL? {
        let result = Command.run(binaryPath, ["config", "file"], timeout: 10)
        guard result.succeeded else { return nil }
        return parseLocation(result.output)
    }

    static func parseLocation(_ output: String) -> URL? {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last, last.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: last)
    }
}

/// Whether rclone.conf is locked, from the file itself (the source of truth)
/// plus whether Nimbus holds the key.
enum ConfigEncryptionState: Equatable, Sendable {
    case plain
    case locked
    /// Encrypted, but not with a key Nimbus has (deleted Keychain item, or the
    /// user encrypted it themselves).
    case lockedWithoutKey

    init(fileIsEncrypted: Bool, keyExists: Bool) {
        switch (fileIsEncrypted, keyExists) {
        case (false, _): self = .plain
        case (true, true): self = .locked
        case (true, false): self = .lockedWithoutKey
        }
    }

    static func read(binaryPath: String, password: KeychainConfigPassword = .standard) -> ConfigEncryptionState? {
        guard let url = RcloneConfigFile.locate(binaryPath: binaryPath) else { return nil }
        return ConfigEncryptionState(
            fileIsEncrypted: RcloneConfigFile.isEncrypted(at: url),
            keyExists: password.exists()
        )
    }

    static let lockedWithoutKeyMessage =
        "rclone.conf is locked with a password Nimbus doesn't have."
}

/// The environment every rclone child gets. rclone only runs the password
/// command when it meets an encrypted config, so it is always set; a value the
/// user exported themselves wins.
enum RcloneEnvironment {
    static let passwordCommandKey = "RCLONE_PASSWORD_COMMAND"
    static let configPassKey = "RCLONE_CONFIG_PASS"

    static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        password: KeychainConfigPassword = .standard
    ) -> [String: String] {
        var environment = base
        if environment[passwordCommandKey] == nil && environment[configPassKey] == nil {
            environment[passwordCommandKey] = password.passwordCommand
        }
        return environment
    }
}

/// Turns encryption on or off for one config file. Blocking; run it detached,
/// with the daemon stopped and no NFS servers running (they would write the
/// config back in plain text on their next token refresh).
struct ConfigEncryptor: Sendable {
    let binaryPath: String
    let configURL: URL
    var password: KeychainConfigPassword = .standard

    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "config-encryption")

    init(binaryPath: String, configURL: URL, password: KeychainConfigPassword = .standard) {
        self.binaryPath = binaryPath
        self.configURL = configURL
        self.password = password
    }

    var backupURL: URL {
        configURL.deletingLastPathComponent()
            .appendingPathComponent(configURL.lastPathComponent + ".nimbus-backup")
    }

    func enable() throws {
        if RcloneConfigFile.isEncrypted(at: configURL) && password.exists() { return }
        try password.createIfMissing()
        try ensureConfigExists()
        try migrate(subcommand: "set", expectEncrypted: true)
        logger.info("rclone.conf locked with the Keychain password")
    }

    func disable() throws {
        guard RcloneConfigFile.isEncrypted(at: configURL) else { return }
        try migrate(subcommand: "remove", expectEncrypted: false)
        logger.info("rclone.conf unlocked")
    }

    /// No remotes yet means no file; give rclone an empty one to encrypt.
    private func ensureConfigExists() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return }
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: configURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw ConfigEncryptionError.configNotFound
        }
    }

    /// Backup, change, verify. The backup is deleted on success (before
    /// enabling it is the plain text we're getting rid of) and restored on
    /// any failure.
    private func migrate(subcommand: String, expectEncrypted: Bool) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL)
        try fm.copyItem(at: configURL, to: backupURL)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)

        let result = Command.run(
            binaryPath,
            ["config", "encryption", subcommand,
             "--config", configURL.path,
             "--password-command", password.passwordCommand],
            environment: Self.migrationEnvironment()
        )

        guard result.succeeded, RcloneConfigFile.isEncrypted(at: configURL) == expectEncrypted else {
            restoreBackup()
            if !result.succeeded {
                throw ConfigEncryptionError.rclone(Self.lastLine(result.error))
            }
            throw ConfigEncryptionError.notApplied
        }
        try? fm.removeItem(at: backupURL)
    }

    private func restoreBackup() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.removeItem(at: configURL)
        do {
            try fm.moveItem(at: backupURL, to: configURL)
            logger.warning("Config change failed; restored rclone.conf from backup")
        } catch {
            logger.error("Config change failed and the backup could not be restored: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The explicit `--password-command` must be the only password source.
    private static func migrationEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[RcloneEnvironment.passwordCommandKey] = nil
        environment[RcloneEnvironment.configPassKey] = nil
        return environment
    }

    private static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
