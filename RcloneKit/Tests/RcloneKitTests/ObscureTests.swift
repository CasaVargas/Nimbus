import Foundation
import Testing
@testable import RcloneKit

struct ObscureTests {
    /// Produced by rclone 1.75.1's `core/obscure` for "hunter2secret".
    /// rclone's obscure is AES-256-CTR under a fixed key with a random IV
    /// prepended, so re-encrypting with that same IV must reproduce it.
    private let rcloneOutput = "OzOtPMzHdeLVllG8Oz05q6yWfIgMtenIIu8e-xk"

    @Test func matchesRcloneForTheSameIV() throws {
        let raw = try #require(RcloneObscure.decodeBase64URL(rcloneOutput))
        let iv = raw.prefix(16)
        #expect(RcloneObscure.obscure("hunter2secret", iv: Data(iv)) == rcloneOutput)
    }

    @Test func revealInvertsObscure() {
        for clear in ["hunter2secret", "", "ü-ñ 🔐 long pass phrase over a block boundary"] {
            #expect(RcloneObscure.reveal(RcloneObscure.obscure(clear)) == clear)
        }
    }

    @Test func usesAFreshIVEachCall() {
        #expect(RcloneObscure.obscure("same") != RcloneObscure.obscure("same"))
    }

    @Test func revealRejectsPlainText() {
        // The exact failure in #109: a plaintext password handed to reveal.
        #expect(RcloneObscure.reveal("hunter2secret") == nil)
    }

    /// End-to-end against the real binary when one is installed.
    @Test func realRcloneRevealsIt() throws {
        let candidates = ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["reveal", RcloneObscure.obscure("hunter2secret")]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "hunter2secret")
    }
}
