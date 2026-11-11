import Foundation
import Testing
@testable import Nimbus

/// A Keychain item under a throwaway service name, deleted afterwards.
private func scratchPassword() -> KeychainConfigPassword {
    KeychainConfigPassword(service: "app.casavargas.nimbus.tests-\(UUID().uuidString)", account: "rclone-config")
}

/// Reads the secret the way rclone does: by running the password command.
private func readSecret(_ password: KeychainConfigPassword) -> String? {
    let parts = password.passwordCommand.split(separator: " ").map(String.init)
    let result = Command.run(parts[0], Array(parts.dropFirst()))
    guard result.succeeded else { return nil }
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite("Config encryption: Keychain", .serialized)
struct KeychainConfigPasswordTests {
    @Test func createReadDeleteRoundTrip() throws {
        let password = scratchPassword()
        defer { try? password.delete() }

        #expect(!password.exists())
        #expect(try password.createIfMissing())
        #expect(password.exists())

        let secret = try #require(readSecret(password))
        #expect(Data(base64Encoded: secret)?.count == 32)

        try password.delete()
        #expect(!password.exists())
    }

    @Test func secondCreateReusesTheExistingItem() throws {
        let password = scratchPassword()
        defer { try? password.delete() }

        try password.createIfMissing()
        let first = try #require(readSecret(password))
        #expect(try password.createIfMissing() == false)
        #expect(readSecret(password) == first)
    }

    @Test func secretNeverReachesArgvOrEnvironment() throws {
        let password = scratchPassword()
        defer { try? password.delete() }
        try password.createIfMissing()
        let secret = try #require(readSecret(password))

        let environment = RcloneEnvironment.childEnvironment(base: [:], password: password)
        #expect(environment[RcloneEnvironment.passwordCommandKey] == password.passwordCommand)
        #expect(!environment.values.contains { $0.contains(secret) })
        #expect(!password.passwordCommand.contains(secret))
    }
}

@Suite("Config encryption: wiring")
@MainActor
struct ConfigEncryptionWiringTests {
    private let standardCommand =
        "/usr/bin/security find-generic-password -s app.casavargas.nimbus -a rclone-config -w"

    @Test func passwordCommandAndExportLine() {
        #expect(KeychainConfigPassword.standard.passwordCommand == standardCommand)
        #expect(KeychainConfigPassword.standard.exportLine == "export RCLONE_PASSWORD_COMMAND='\(standardCommand)'")
    }

    @Test func childEnvironmentAddsPasswordCommandAndKeepsTheRest() {
        let environment = RcloneEnvironment.childEnvironment(base: ["HOME": "/Users/x"])
        #expect(environment["HOME"] == "/Users/x")
        #expect(environment["RCLONE_PASSWORD_COMMAND"] == standardCommand)
    }

    @Test func userPasswordSettingsWin() {
        let own = RcloneEnvironment.childEnvironment(base: ["RCLONE_PASSWORD_COMMAND": "pass rclone"])
        #expect(own["RCLONE_PASSWORD_COMMAND"] == "pass rclone")

        let plain = RcloneEnvironment.childEnvironment(base: ["RCLONE_CONFIG_PASS": "x"])
        #expect(plain["RCLONE_PASSWORD_COMMAND"] == nil)
    }

    @Test func daemonProcessGetsPasswordCommandOnly() {
        let process = RcloneDaemon.makeProcess(
            binaryPath: "/opt/homebrew/bin/rclone",
            port: 5572,
            bandwidthLimit: "",
            concurrentTransfers: 4,
            baseEnvironment: ["PATH": "/usr/bin"]
        )
        #expect(process.environment == ["PATH": "/usr/bin", "RCLONE_PASSWORD_COMMAND": standardCommand])
        #expect(process.arguments?.first == "rcd")
        #expect(!(process.arguments ?? []).contains { $0.contains("password") })
        #expect(process.standardInput as? FileHandle == FileHandle.nullDevice)
    }

    @Test func nfsProcessGetsPasswordCommandOnly() {
        let process = MountManager.makeNFSProcess(
            binaryPath: "/opt/homebrew/bin/rclone",
            remote: "gdrive:",
            port: 19049,
            readOnly: false,
            baseEnvironment: ["PATH": "/usr/bin"]
        )
        #expect(process.environment == ["PATH": "/usr/bin", "RCLONE_PASSWORD_COMMAND": standardCommand])
        #expect(Array((process.arguments ?? []).prefix(3)) == ["serve", "nfs", "gdrive:"])
        #expect(!(process.arguments ?? []).contains { $0.contains("password") })
        #expect(process.standardInput as? FileHandle == FileHandle.nullDevice)
    }

    @Test func stateFollowsFileAndKey() {
        #expect(ConfigEncryptionState(fileIsEncrypted: false, keyExists: false) == .plain)
        #expect(ConfigEncryptionState(fileIsEncrypted: false, keyExists: true) == .plain)
        #expect(ConfigEncryptionState(fileIsEncrypted: true, keyExists: true) == .locked)
        #expect(ConfigEncryptionState(fileIsEncrypted: true, keyExists: false) == .lockedWithoutKey)
    }

    @Test func headerDetection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigHeader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let locked = dir.appendingPathComponent("locked.conf")
        try Data("# Encrypted rclone configuration File\n\nRCLONE_ENCRYPT_V0:\nabc".utf8).write(to: locked)
        let plain = dir.appendingPathComponent("plain.conf")
        try Data("[demo]\ntype = s3\n".utf8).write(to: plain)

        #expect(RcloneConfigFile.isEncrypted(at: locked))
        #expect(!RcloneConfigFile.isEncrypted(at: plain))
        #expect(!RcloneConfigFile.isEncrypted(at: dir.appendingPathComponent("missing.conf")))
    }

    @Test func parsesRcloneConfigFileOutput() {
        let output = "Configuration file is stored at:\n/Users/x/.config/rclone/rclone.conf\n"
        #expect(RcloneConfigFile.parseLocation(output)?.path == "/Users/x/.config/rclone/rclone.conf")
        #expect(RcloneConfigFile.parseLocation("garbage") == nil)
    }

    @Test func switchIsBlockedWhileRcloneChildrenHoldTheConfig() {
        #expect(ConfigEncryptionModel.blockReason(state: .plain, connectedNetworkDrives: 0,
                                                  transfersRunning: false, backupsRunning: false) == nil)
        #expect(ConfigEncryptionModel.blockReason(state: .plain, connectedNetworkDrives: 1,
                                                  transfersRunning: false, backupsRunning: false)
                == "Disconnect your network drives first.")
        #expect(ConfigEncryptionModel.blockReason(state: .locked, connectedNetworkDrives: 0,
                                                  transfersRunning: true, backupsRunning: false)
                == "Wait for transfers and backups to finish.")
        #expect(ConfigEncryptionModel.blockReason(state: .plain, connectedNetworkDrives: 0,
                                                  transfersRunning: false, backupsRunning: true)
                == "Wait for transfers and backups to finish.")
        #expect(ConfigEncryptionModel.blockReason(state: .lockedWithoutKey, connectedNetworkDrives: 0,
                                                  transfersRunning: false, backupsRunning: false)
                == ConfigEncryptionState.lockedWithoutKeyMessage)
    }
}

/// Real rclone, scratch config, scratch Keychain item. Opt-in like
/// BackupLiveTests:
///
///     TEST_RUNNER_NIMBUS_LIVE_RCLONE=/opt/homebrew/bin/rclone xcodebuild test \
///       -only-testing:NimbusTests/ConfigEncryptionLiveTests …
@Suite("ConfigEncryptionLive", .serialized, .enabled(if: LiveRclone.path != nil))
struct ConfigEncryptionLiveTests {
    private func scratchConfig(_ contents: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigEncLive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rclone.conf")
        if let contents { try Data(contents.utf8).write(to: url) }
        return url
    }

    private func listRemotes(_ config: URL, _ password: KeychainConfigPassword) -> CommandResult {
        var environment = ProcessInfo.processInfo.environment
        environment["RCLONE_PASSWORD_COMMAND"] = password.passwordCommand
        return Command.run(LiveRclone.path!, ["listremotes", "--config", config.path], environment: environment)
    }

    @Test func lockAndUnlockRoundTrip() throws {
        let password = scratchPassword()
        defer { try? password.delete() }
        let config = try scratchConfig("""
        [s3demo]
        type = s3
        access_key_id = AKIAEXAMPLE
        secret_access_key = sekrit

        [drive]
        type = drive
        token = {"access_token":"ya29.example"}

        """)
        defer { try? FileManager.default.removeItem(at: config.deletingLastPathComponent()) }
        let encryptor = ConfigEncryptor(binaryPath: LiveRclone.path!, configURL: config, password: password)

        try encryptor.enable()
        let locked = try String(contentsOf: config, encoding: .utf8)
        #expect(locked.hasPrefix(RcloneConfigFile.encryptedHeader))
        #expect(!locked.contains("access_key_id"))
        #expect(!locked.contains("token"))
        #expect(!FileManager.default.fileExists(atPath: encryptor.backupURL.path))
        #expect(ConfigEncryptionState(fileIsEncrypted: RcloneConfigFile.isEncrypted(at: config),
                                      keyExists: password.exists()) == .locked)

        let listed = listRemotes(config, password)
        #expect(listed.succeeded)
        #expect(listed.output.contains("s3demo:"))
        #expect(listed.output.contains("drive:"))

        try encryptor.disable()
        let unlocked = try String(contentsOf: config, encoding: .utf8)
        #expect(unlocked.contains("access_key_id = AKIAEXAMPLE"))
        #expect(!FileManager.default.fileExists(atPath: encryptor.backupURL.path))
        #expect(password.exists(), "Unlocking keeps the Keychain item for next time")
    }

    @Test func locksAMissingConfig() throws {
        let password = scratchPassword()
        defer { try? password.delete() }
        let config = try scratchConfig(nil)
        defer { try? FileManager.default.removeItem(at: config.deletingLastPathComponent()) }

        try ConfigEncryptor(binaryPath: LiveRclone.path!, configURL: config, password: password).enable()
        #expect(RcloneConfigFile.isEncrypted(at: config))
        #expect(listRemotes(config, password).succeeded)
    }

    @Test func failedLockRestoresTheBackup() throws {
        // Encrypted with someone else's password: Nimbus's key can't open it.
        let theirs = scratchPassword()
        let ours = scratchPassword()
        defer { try? theirs.delete(); try? ours.delete() }
        let config = try scratchConfig("[a]\ntype = local\n")
        defer { try? FileManager.default.removeItem(at: config.deletingLastPathComponent()) }
        try ConfigEncryptor(binaryPath: LiveRclone.path!, configURL: config, password: theirs).enable()
        let before = try Data(contentsOf: config)

        let encryptor = ConfigEncryptor(binaryPath: LiveRclone.path!, configURL: config, password: ours)
        #expect(throws: ConfigEncryptionError.self) { try encryptor.disable() }
        #expect(try Data(contentsOf: config) == before)
        #expect(!FileManager.default.fileExists(atPath: encryptor.backupURL.path))
    }

    @Test func locatesTheConfigRcloneUses() throws {
        let url = try #require(RcloneConfigFile.locate(binaryPath: LiveRclone.path!))
        #expect(url.lastPathComponent.hasSuffix(".conf"))
    }
}
