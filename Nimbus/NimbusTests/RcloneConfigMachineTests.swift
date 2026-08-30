import Testing
import Foundation

/// Locates the rclone binary. Hoisted out of `RcloneConfigMachineTests` (rather
/// than a static member of that type) because the suite's own `.enabled(if:)`
/// trait needs to read it, and referencing a type's static member from an
/// attribute attached to that same type is a circular reference.
private enum RcloneLocator {
    static var path: String? {
        let candidates = ["/usr/local/bin/rclone", "/opt/homebrew/bin/rclone"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Pins the rclone behavior the guided Add Remote flow depends on. Skipped
/// (not silently passed) when rclone isn't installed. Uses
/// `rclone rc --loopback`, which runs the RC method in-process against a
/// throwaway config file — no daemon needed.
@Suite(
    "RcloneConfigMachine", .serialized,
    .enabled(if: RcloneLocator.path != nil, "requires an rclone binary on PATH")
)
struct RcloneConfigMachineTests {

    private func loopback(_ configPath: String, _ args: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: RcloneLocator.path!)
        process.arguments = ["rc", "--loopback"] + args
        var env = ProcessInfo.processInfo.environment
        env["RCLONE_CONFIG"] = configPath
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Walks the machine with default answers, returning the questions asked.
    /// Uses its own throwaway config file per call — the walks mutate config
    /// state, so sharing one file across calls/tests would make them order-dependent.
    private func walk(type: String, askAll: Bool, answers: [String: String]) throws -> [String] {
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).conf").path
        FileManager.default.createFile(atPath: configPath, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        var asked: [String] = []
        var opt: [String: Any] = ["nonInteractive": true, "all": askAll]
        for _ in 0..<200 {
            let optJSON = String(
                data: try JSONSerialization.data(withJSONObject: opt), encoding: .utf8
            )!
            let response = try loopback(configPath, [
                "config/create", "name=canary", "type=\(type)",
                "parameters={}", "opt=\(optJSON)",
            ])
            let state = response["State"] as? String ?? ""
            guard let option = response["Option"] as? [String: Any],
                  !state.isEmpty else { break }
            let name = option["Name"] as? String ?? "?"
            asked.append(name)
            opt = [
                "nonInteractive": true, "all": askAll, "continue": true,
                "state": state, "result": answers[name] ?? "",
            ]
        }
        return asked
    }

    @Test func askAllWalksAreShortBecauseRcloneGatesByProvider() throws {
        #expect(try walk(type: "s3", askAll: true,
                         answers: ["provider": "AWS", "env_auth": "false"]).count == 13)
        #expect(try walk(type: "drive", askAll: true, answers: [:]).count == 8)
        #expect(try walk(type: "sftp", askAll: true, answers: [:]).count == 14)
    }

    @Test func askAllTrueWalksEndAtTheAdvancedGate() throws {
        let asked = try walk(type: "s3", askAll: true,
                             answers: ["provider": "AWS", "env_auth": "false"])
        #expect(asked.last == "config_fs_advanced")
    }

    @Test func askAllFalseReachesOAuthOnDriveAndAsksNothingOnSftp() throws {
        // The asymmetry the flow's strategy selection depends on.
        #expect(try walk(type: "drive", askAll: false, answers: [:]).first == "config_is_local")
        #expect(try walk(type: "sftp", askAll: false, answers: [:]).isEmpty)
    }
}
