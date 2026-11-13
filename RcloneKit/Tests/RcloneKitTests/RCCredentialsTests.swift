import Foundation
import Testing
@testable import RcloneKit

struct RCCredentialsTests {
    @Test func randomPasswordsAreLongAndUnique() {
        let a = RCCredentials.random(), b = RCCredentials.random()
        #expect(a.password != b.password)
        #expect(a.password.count >= 43)  // 32 bytes, base64url
        #expect(!a.password.contains { "+/=".contains($0) })
    }

    @Test func authorizationHeaderIsBasic() {
        let header = RCCredentials(user: "u", password: "p").authorizationHeader
        #expect(header == "Basic dTpw")
    }

    @Test func environmentUsesRcloneRCVariables() {
        let env = RCCredentials(user: "u", password: "p").environment
        #expect(env == ["RCLONE_RC_USER": "u", "RCLONE_RC_PASS": "p"])
    }

    /// Against a real `rclone rcd` started the way Nimbus starts it: an
    /// authenticated client works for RPC and `--rc-serve` downloads, an
    /// unauthenticated one is refused.
    @Test func realDaemonRequiresTheCredentials() async throws {
        let candidates = ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"]
        guard let rclone = candidates.first(where: FileManager.default.isExecutableFile) else { return }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcauth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("rclone.conf")
        try Data("[loc]\ntype = local\n".utf8).write(to: config)
        try Data("hello".utf8).write(to: dir.appendingPathComponent("f.txt"))

        let port = Int.random(in: 41000...41999)
        let credentials = RCCredentials.random()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rclone)
        process.arguments = ["rcd", "--rc-addr", "127.0.0.1:\(port)", "--rc-serve", "--config", config.path]
        process.environment = ProcessInfo.processInfo.environment.merging(credentials.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }

        let authed = RcloneClient(port: port, credentials: credentials)
        var up = false
        for _ in 0..<50 where !up {
            up = await authed.healthCheck()
            if !up { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(up)

        let anonymous = RcloneClient(port: port)
        #expect(await anonymous.healthCheck() == false)
        let wrong = RcloneClient(port: port, credentials: RCCredentials(user: "nimbus", password: "nope"))
        #expect(await wrong.healthCheck() == false)

        let out = dir.appendingPathComponent("out.txt")
        try await authed.downloadFile(fs: "loc:\(dir.path)", remote: "f.txt", to: out)
        #expect(try String(contentsOf: out, encoding: .utf8) == "hello")
        await #expect(throws: RcloneError.self) {
            try await anonymous.downloadFile(fs: "loc:\(dir.path)", remote: "f.txt", to: out)
        }
    }
}
