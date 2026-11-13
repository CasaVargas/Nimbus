import Foundation
import Testing
import RcloneKit
@testable import Nimbus

@Suite("RcloneDaemon settings")
@MainActor
struct RcloneDaemonSettingsTests {
    @Test func launchArgumentsCarryPersistedTransferSettings() {
        let arguments = RcloneDaemon.launchArguments(
            port: 5572,
            bandwidthLimit: "12M",
            concurrentTransfers: 7
        )

        #expect(arguments.contains("--bwlimit"))
        #expect(arguments.contains("12M"))
        #expect(arguments.contains("--transfers"))
        #expect(arguments.contains("7"))
    }

    @Test func emptyPersistedBandwidthLaunchesWithRcloneOff() {
        let arguments = RcloneDaemon.launchArguments(
            port: 5572,
            bandwidthLimit: "",
            concurrentTransfers: 4
        )

        let limitIndex = try! #require(arguments.firstIndex(of: "--bwlimit"))
        #expect(arguments[arguments.index(after: limitIndex)] == "off")
    }

    /// Security regression guard: the RC API dumps every credential and
    /// serves file contents, so it must never run unauthenticated or answer
    /// cross-origin requests.
    @Test func launchArgumentsRequireAuthAndSendNoCORSHeaders() {
        let arguments = RcloneDaemon.launchArguments(
            port: 5572, bandwidthLimit: "", concurrentTransfers: 4
        )
        #expect(!arguments.contains("--rc-no-auth"))
        #expect(!arguments.contains { $0.hasPrefix("--rc-allow-origin") })
        #expect(arguments.contains("127.0.0.1:5572"))
    }

    @Test func rcPasswordTravelsInTheEnvironmentNotArgv() {
        let credentials = RCCredentials(user: "nimbus", password: "s3cret-value")
        let process = RcloneDaemon.makeProcess(
            binaryPath: "/opt/homebrew/bin/rclone", port: 5572, credentials: credentials,
            bandwidthLimit: "", concurrentTransfers: 4, baseEnvironment: [:]
        )
        #expect(!(process.arguments ?? []).contains { $0.contains("s3cret-value") || $0.hasPrefix("--rc-pass") })
        #expect(process.environment?["RCLONE_RC_USER"] == "nimbus")
        #expect(process.environment?["RCLONE_RC_PASS"] == "s3cret-value")
    }

    @Test func changingConfiguredPathRequiresRestart() {
        let daemon = makeConnectedDaemon(activePath: "/a/rclone")

        #expect(daemon.restartRequired(for: "/b/rclone"))
        #expect(!daemon.restartRequired(for: "/a/rclone"))
    }

    @Test func disconnectedDaemonDoesNotRequireRestart() {
        let daemon = RcloneDaemon()

        #expect(!daemon.restartRequired(for: "/b/rclone"))
    }

    @Test func restartWaitsForInitialStaleDaemonCleanupBeforeLaunching() async throws {
        let cleanup = SuspendedAsyncOperation()
        let binaryPath = try makeRcloneStub()
        let daemon = RcloneDaemon(
            testStatus: .idle,
            testStartupHooks: .init(
                staleDaemonCleanup: { await cleanup.perform() },
                availablePort: { 5572 },
                rcloneVersion: { _ in "rclone v1.70.0" },
                healthCheck: { false }
            )
        )
        defer {
            daemon.stop()
            try? FileManager.default.removeItem(at: binaryPath.deletingLastPathComponent())
        }

        let initialStart = Task { await daemon.start(binaryPath: binaryPath.path) }
        await cleanup.waitUntilStarted()

        daemon.stop()
        let restartedStart = Task { await daemon.start(binaryPath: binaryPath.path) }
        await Task.yield()
        await Task.yield()

        #expect(daemon.status == .starting)
        #expect(daemon.activeBinaryPath == nil)

        await cleanup.release()
        await initialStart.value
        daemon.stop()
        await restartedStart.value
    }

    @Test func supersededStartCannotSetFailureAfterFinalRetryDelay() async throws {
        let oldRetryDelay = SuspendedAsyncOperation()
        let replacementRetryDelay = SuspendedAsyncOperation()
        let retryDelays = OrderedRetryDelays(
            first: oldRetryDelay,
            second: replacementRetryDelay
        )
        let binaryPath = try makeRcloneStub()
        let daemon = RcloneDaemon(
            testStatus: .idle,
            testStartupHooks: .init(
                staleDaemonCleanup: {},
                availablePort: { 5572 },
                rcloneVersion: { _ in "rclone v1.70.0" },
                healthCheck: { false },
                healthRetryDelay: { await retryDelays.perform() },
                maxHealthCheckAttempts: 1
            )
        )
        defer {
            daemon.stop()
            try? FileManager.default.removeItem(at: binaryPath.deletingLastPathComponent())
        }

        let oldStart = Task { await daemon.start(binaryPath: binaryPath.path) }
        await oldRetryDelay.waitUntilStarted()

        let replacementStart = Task { await daemon.restart(binaryPath: binaryPath.path) }
        await replacementRetryDelay.waitUntilStarted()

        await oldRetryDelay.release()
        await oldStart.value

        #expect(daemon.status == .starting)

        daemon.stop()
        await replacementRetryDelay.release()
        await replacementStart.value
    }

    private func makeConnectedDaemon(activePath: String) -> RcloneDaemon {
        RcloneDaemon(testStatus: .connected, activeBinaryPath: activePath)
    }

    private func makeRcloneStub() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nimbus-RcloneDaemonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binaryPath = directory.appendingPathComponent("rclone")
        let script = """
        #!/bin/sh
        if [ \"$1\" = \"version\" ]; then
            printf 'rclone v1.70.0\\n'
            exit 0
        fi
        while true; do
            sleep 1
        done
        """
        try Data(script.utf8).write(to: binaryPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binaryPath.path)
        return binaryPath
    }
}

private actor SuspendedAsyncOperation {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func perform() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor OrderedRetryDelays {
    private var count = 0
    private let first: SuspendedAsyncOperation
    private let second: SuspendedAsyncOperation

    init(first: SuspendedAsyncOperation, second: SuspendedAsyncOperation) {
        self.first = first
        self.second = second
    }

    func perform() async {
        count += 1
        if count == 1 {
            await first.perform()
        } else {
            await second.perform()
        }
    }
}
