import Foundation
import Testing
import RcloneKit
@testable import Nimbus

/// End-to-end compare against a real rclone on a scratch local tree.
/// Opt-in, because it spawns `rclone rcd` (on a port outside the app's
/// 5572–5580 range, so it never touches a running Nimbus):
///
///     TEST_RUNNER_NIMBUS_LIVE_RCLONE=/opt/homebrew/bin/rclone xcodebuild test \
///       -only-testing:NimbusTests/CompareLiveTests …
@Suite("CompareLive", .serialized, .enabled(if: LiveRclone.path != nil))
@MainActor
struct CompareLiveTests {
    static let port = 5597

    @Test func comparesTwoLocalFolders() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CompareLive-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try fm.createDirectory(at: a.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }
        try write("same", a.appendingPathComponent("same file.txt"))
        try write("same", b.appendingPathComponent("same file.txt"))
        try write("one", a.appendingPathComponent("diff.txt"))
        try write("two!", b.appendingPathComponent("diff.txt"))
        try write("x", a.appendingPathComponent("sub/onlyA.txt"))
        try write("y", b.appendingPathComponent("onlyB.txt"))

        let config = root.appendingPathComponent("empty.conf")
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

        let model = CompareViewModel(client: client, pollInterval: .milliseconds(50))
        await model.compare(.local(path: a.path), .local(path: b.path), method: .checksum)
        guard case .finished(let result) = model.state else {
            Issue.record("compare did not finish: \(model.state)")
            return
        }
        #expect(result.same == ["same file.txt"])
        #expect(result.differ == ["diff.txt"])
        #expect(result.onlyInA == ["sub/onlyA.txt"])
        #expect(result.onlyInB == ["onlyB.txt"])
        #expect(result.errors.isEmpty)
        #expect(!result.comparedWithoutHash)

        await model.compare(.local(path: a.path), .local(path: a.path), method: .sizeOnly)
        guard case .finished(let same) = model.state else {
            Issue.record("self-compare did not finish: \(model.state)")
            return
        }
        #expect(same.matches)
        #expect(same.same.count == 3)

        // An unknown remote is a failure, not "everything missing".
        await model.compare(.cloud(remote: "nosuchremote", path: ""), .local(path: b.path), method: .checksum)
        guard case .failed = model.state else {
            Issue.record("expected failure, got \(model.state)")
            return
        }
    }
}
