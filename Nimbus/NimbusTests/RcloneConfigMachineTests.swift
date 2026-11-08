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

    /// A broken rclone invocation must never look like "no more questions" —
    /// see `loopback` below.
    private struct RcloneInvocationFailure: Error, CustomStringConvertible {
        var description: String
    }

    /// Thread-safe accumulator for a background pipe-drain. `@unchecked
    /// Sendable` because the semaphore in `loopback` below establishes a real
    /// happens-before edge between the write and the read; the compiler can't
    /// see that, matching how `RcloneKit` is `@unchecked Sendable` for the
    /// same kind of externally-synchronized reason.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private func loopback(_ configPath: String, _ args: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: RcloneLocator.path!)
        process.arguments = ["rc", "--loopback"] + args
        var env = ProcessInfo.processInfo.environment
        env["RCLONE_CONFIG"] = configPath
        process.environment = env
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        // Drain stdout and stderr concurrently. Reading them one at a time
        // (as the original brief did, discarding stderr's Pipe unread) can
        // deadlock: once either pipe's OS buffer fills, the child blocks
        // writing to it while we're still blocked reading the other one.
        let stderrBox = DataBox()
        let stderrDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDrained.signal()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stderrDrained.wait()
        process.waitUntilExit()

        // A crashed, misinvoked, or otherwise-broken rclone must fail loudly,
        // not decay into "[:]" — which `walk` below reads identically to a
        // legitimate "state machine finished, no more questions" response.
        // That equivalence is exactly what let this canary false-green.
        //
        // The signal for "broken" is JSON-parseability, not exit code.
        // rclone's RC endpoint always emits a well-formed JSON object on
        // stdout, even when a step is rejected — e.g. answering the OAuth
        // gate non-interactively fails with exit 1 and a perfectly valid
        // `{"error": "...", "path": "...", "status": 500}` body. `walk`
        // already treats that shape (no "State"/"Option") as a legitimate
        // stop, exactly like a clean `{}` finish, and that's correct: it's
        // rclone answering, just answering "no". A *broken* invocation
        // (wrong flag, missing binary, a crash before rclone can print)
        // leaves stdout empty or non-JSON — nothing else does, per rclone's
        // own contract — so that's the one condition this throws on.
        guard let json = (try? JSONSerialization.jsonObject(with: stdoutData)) as? [String: Any] else {
            let stderrText = String(data: stderrBox.data, encoding: .utf8) ?? "<non-utf8 stderr>"
            let stdoutPreview = String(data: stdoutData.prefix(200), encoding: .utf8) ?? "<non-utf8 stdout>"
            throw RcloneInvocationFailure(
                description: "rclone exited \(process.terminationStatus) for args \(args) and produced no parseable JSON object on stdout — first 200 bytes: \(stdoutPreview) — stderr: \(stderrText)"
            )
        }
        return json
    }

    /// One question the machine asked: the option name and its state cursor.
    private struct Asked: Equatable {
        let name: String
        let state: String
    }

    /// The answer `RemoteSetupFlow` gives Drive's rclone 1.76 shared
    /// client_id warning on the user's behalf. Walks that model the app's
    /// path pass it so they follow the same branch the app does.
    private let nimbusAnswers = ["config_shared_client_id": "true"]

    /// Walks the machine with default answers, returning the option names asked.
    private func walk(type: String, askAll: Bool, answers: [String: String]) throws -> [String] {
        try walkSteps(type: type, askAll: askAll, answers: answers).map(\.name)
    }

    /// Walks the machine with default answers, returning every question asked.
    /// Uses its own throwaway config file per call — the walks mutate config
    /// state, so sharing one file across calls/tests would make them order-dependent.
    private func walkSteps(type: String, askAll: Bool, answers: [String: String]) throws -> [Asked] {
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).conf").path
        FileManager.default.createFile(atPath: configPath, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        var asked: [Asked] = []
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
            asked.append(Asked(name: name, state: state))
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
        // rclone 1.76 added `config_shared_client_id` after Drive's advanced
        // gate (8 steps before). Answered the way the app answers it.
        #expect(try walk(type: "drive", askAll: true, answers: nimbusAnswers).count == 9)
        #expect(try walk(type: "sftp", askAll: true, answers: [:]).count == 14)
    }

    @Test func askAllTrueWalksEndAtTheAdvancedGate() throws {
        let asked = try walk(type: "s3", askAll: true,
                             answers: ["provider": "AWS", "env_auth": "false"])
        #expect(asked.last == "config_fs_advanced")
    }

    @Test func askAllFalseReachesOAuthOnDriveAndAsksNothingOnSftp() throws {
        // The asymmetry the flow's strategy selection depends on.
        //
        // The sftp assertion below hinges on `.isEmpty` meaning "rclone
        // legitimately asked nothing," not "the call to rclone failed."
        // `walk` can only return without throwing if every `loopback` call
        // it made produced a parseable rclone RC response (see `loopback`'s
        // guard above) — so `try walk(...)` succeeding already proves rclone
        // was actually invoked and actually answered; `.isEmpty` on that
        // proven-real response is what then proves it answered "no
        // questions". Both conditions are required to reach the assertion
        // at all, not just the second one.
        //
        // Since rclone 1.76 Drive's first `all:false` step is a plain
        // question, `config_shared_client_id` at state `client_id_warning`
        // (the shared client_id is being retired; default false). Answering
        // it "true", as RemoteSetupFlow does on the user's behalf, leads
        // straight to the `*oauth-islocal` state the flow detects OAuth by.
        // If rclone ever drops the question or adds another one ahead of
        // OAuth, this fails and the flow's `automaticAnswers` needs a look.
        let drive = try walkSteps(type: "drive", askAll: false, answers: nimbusAnswers)
        #expect(drive.first == Asked(name: "config_shared_client_id", state: "client_id_warning"))
        #expect(drive.dropFirst().first?.name == "config_is_local")
        #expect(drive.dropFirst().first?.state.hasPrefix("*oauth-islocal") == true)
        #expect(try walk(type: "sftp", askAll: false, answers: [:]).isEmpty)
    }
}
