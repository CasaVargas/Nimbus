import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// "New Encrypted Folder" against a real rclone on a scratch config and a
/// scratch local folder. Opt-in, like the other live suites:
///
///     TEST_RUNNER_NIMBUS_LIVE_RCLONE=/opt/homebrew/bin/rclone xcodebuild test \
///       -only-testing:NimbusTests/EncryptedFolderLiveTests …
@Suite("EncryptedFolderLive", .serialized, .enabled(if: LiveRclone.path != nil))
@MainActor
struct EncryptedFolderLiveTests {
    static let port = 5596

    @Test func createsReconnectsAndRefusesWrongPassword() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("EncryptedFolderLive-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = root.appendingPathComponent("Vault")
        let config = root.appendingPathComponent("rclone.conf")
        try Data().write(to: config)

        let daemon = Process()
        daemon.executableURL = URL(fileURLWithPath: LiveRclone.path!)
        daemon.arguments = ["rcd", "--config", config.path, "--rc-no-auth", "--rc-addr", "127.0.0.1:\(Self.port)"]
        daemon.standardOutput = FileHandle.nullDevice
        daemon.standardError = FileHandle.nullDevice
        try daemon.run()
        defer { daemon.terminate() }
        let client = RcloneClient(port: Self.port)
        for _ in 0..<50 where (try? await client.listJobs()) == nil {
            try await Task.sleep(for: .milliseconds(100))
        }

        func setup(password: String, existing: Set<String>) -> EncryptedFolderSetup {
            let setup = EncryptedFolderSetup(client: client, existingNames: existing)
            setup.folder = .local(path: base.path)
            setup.password = password
            setup.confirmation = password
            setup.acknowledged = true
            return setup
        }

        // 1. New folder: created, crypt remote written with an obscured password and no salt.
        let first = setup(password: "correct horse", existing: [])
        await first.create()
        #expect(first.phase == .created(name: "Vault Encrypted"))
        #expect(fm.fileExists(atPath: base.path))
        let conf = try String(contentsOf: config, encoding: .utf8)
        #expect(conf.contains("[Vault Encrypted]"))
        #expect(conf.contains("type = crypt"))
        #expect(conf.contains("remote = \(base.path)"))
        #expect(!conf.contains("correct horse"))
        #expect(conf.contains("password = "))
        #expect(!conf.contains("password2"))

        // 2. A file written through it lands scrambled.
        let plain = root.appendingPathComponent("secret-report.txt")
        try Data("top secret".utf8).write(to: plain)
        try await client.uploadFile(from: plain, fs: "Vault Encrypted:", remote: "")
        let onDisk = try fm.contentsOfDirectory(atPath: base.path)
        #expect(onDisk.count == 1)
        #expect(onDisk.first != "secret-report.txt")
        #expect(try await client.entryNames(fs: "Vault Encrypted:") == ["secret-report.txt"])

        // 3. Same folder, right password, new name: accepted (reconnect).
        let again = setup(password: "correct horse", existing: ["Vault Encrypted"])
        #expect(again.name == "Vault Encrypted 2")
        await again.create()
        #expect(again.phase == .created(name: "Vault Encrypted 2"))

        // 4. Same folder, wrong password: refused and undone.
        let wrong = setup(password: "wrong password", existing: ["Vault Encrypted", "Vault Encrypted 2"])
        await wrong.create()
        guard case .failed = wrong.phase else {
            Issue.record("expected refusal, got \(wrong.phase)")
            return
        }
        #expect(try await !client.listRemotes().contains("Vault Encrypted 3"))
    }
}
