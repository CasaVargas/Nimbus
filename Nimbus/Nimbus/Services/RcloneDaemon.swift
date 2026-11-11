import Foundation
import Observation
import RcloneKit
import os

@Observable
@MainActor
final class RcloneDaemon {
    enum Status: Equatable {
        case idle
        case starting
        case connected
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var port: Int = 5572
    private(set) var activeBinaryPath: String?
    private(set) var rcloneVersion: String?
    let client: RcloneClient

    private var process: Process?
    private var healthTask: Task<Void, Never>?
    private var lifecycleID: UUID?
    private var staleDaemonCleanupTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "daemon")
#if DEBUG
    private let testStartupHooks: TestStartupHooks?
#endif

    private static let portRange = 5572...5580

    init() {
        client = RcloneClient()
#if DEBUG
        testStartupHooks = nil
#endif
    }

#if DEBUG
    struct TestStartupHooks {
        let staleDaemonCleanup: () async -> Void
        let availablePort: () async -> Int?
        let rcloneVersion: (String) async -> String?
        let healthCheck: () async -> Bool
        let healthRetryDelay: (() async -> Void)?
        let maxHealthCheckAttempts: Int

        init(
            staleDaemonCleanup: @escaping () async -> Void,
            availablePort: @escaping () async -> Int?,
            rcloneVersion: @escaping (String) async -> String?,
            healthCheck: @escaping () async -> Bool = { false },
            healthRetryDelay: (() async -> Void)? = nil,
            maxHealthCheckAttempts: Int = 30
        ) {
            self.staleDaemonCleanup = staleDaemonCleanup
            self.availablePort = availablePort
            self.rcloneVersion = rcloneVersion
            self.healthCheck = healthCheck
            self.healthRetryDelay = healthRetryDelay
            self.maxHealthCheckAttempts = maxHealthCheckAttempts
        }
    }

    /// Test fixture initializer. It is excluded from release builds.
    init(
        testStatus: Status,
        activeBinaryPath: String? = nil,
        rcloneVersion: String? = nil,
        port: Int = 5572,
        testStartupHooks: TestStartupHooks? = nil
    ) {
        client = RcloneClient()
        status = testStatus
        self.activeBinaryPath = activeBinaryPath
        self.rcloneVersion = rcloneVersion
        self.port = port
        self.testStartupHooks = testStartupHooks
    }
#endif

    func start(
        binaryPath: String = "/usr/local/bin/rclone",
        bandwidthLimit: String = "",
        concurrentTransfers: Int = 4
    ) async {
        guard status != .connected && status != .starting else { return }
        guard mayStartDaemon else {
            logger.info("Not starting rclone: this process is a test or preview host")
            return
        }
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        status = .starting

        // Every launch shares this gate so restarts cannot race a prior
        // session's still-running stale-daemon cleanup.
        await waitForStaleDaemonCleanup()
        guard isCurrent(lifecycleID) else { return }

        guard let availablePort = await findAvailablePort() else {
            guard isCurrent(lifecycleID) else { return }
            status = .error("No available port in range \(Self.portRange)")
            return
        }
        guard isCurrent(lifecycleID) else { return }
        port = availablePort
        client.updatePort(availablePort)

        let proc = Self.makeProcess(
            binaryPath: binaryPath,
            port: availablePort,
            bandwidthLimit: bandwidthLimit,
            concurrentTransfers: concurrentTransfers
        )

        do {
            try proc.run()
            guard isCurrent(lifecycleID) else {
                proc.terminate()
                return
            }
            process = proc
            activeBinaryPath = binaryPath
            logger.info("Started rclone on port \(availablePort), pid \(proc.processIdentifier)")
        } catch {
            guard isCurrent(lifecycleID) else { return }
            status = .error("Failed to start rclone: \(error.localizedDescription)")
            return
        }

        let version = await readRcloneVersion(at: binaryPath)
        guard isCurrent(lifecycleID) else { return }
        rcloneVersion = version

        let maxAttempts = maximumHealthCheckAttempts
        for attempt in 1...maxAttempts {
            if await healthCheck() {
                guard isCurrent(lifecycleID) else { return }
                status = .connected
                logger.info("Rclone healthy after \(attempt) attempts")
                return
            }
            guard isCurrent(lifecycleID) else { return }
            if !proc.isRunning {
                let locked = await Self.configLockedWithoutKey(binaryPath: binaryPath)
                guard isCurrent(lifecycleID) else { return }
                status = .error(locked ? ConfigEncryptionState.lockedWithoutKeyMessage
                                       : "Rclone process exited unexpectedly")
                return
            }
            await waitForHealthRetry()
            guard isCurrent(lifecycleID) else { return }
        }

        guard isCurrent(lifecycleID) else { return }
        status = .error("Rclone failed to respond after \(maxAttempts) health checks")
    }

    func stop() {
        lifecycleID = nil
        healthTask?.cancel()
        healthTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
            logger.info("Stopped rclone daemon")
        }
        process = nil
        activeBinaryPath = nil
        rcloneVersion = nil
        status = .idle
    }

    func retry(
        binaryPath: String = "/usr/local/bin/rclone",
        bandwidthLimit: String = "",
        concurrentTransfers: Int = 4
    ) async {
        await restart(
            binaryPath: binaryPath,
            bandwidthLimit: bandwidthLimit,
            concurrentTransfers: concurrentTransfers
        )
    }

    func restartRequired(for configuredPath: String) -> Bool {
        status == .connected && activeBinaryPath != configuredPath
    }

    func restart(
        binaryPath: String,
        bandwidthLimit: String = "",
        concurrentTransfers: Int = 4
    ) async {
        stop()
        await start(
            binaryPath: binaryPath,
            bandwidthLimit: bandwidthLimit,
            concurrentTransfers: concurrentTransfers
        )
    }

    /// The configured `rclone rcd` child. Its environment carries the
    /// Keychain password command (never the password), and stdin is
    /// /dev/null so a locked config fails fast instead of waiting for a typed
    /// password.
    static func makeProcess(
        binaryPath: String,
        port: Int,
        bandwidthLimit: String,
        concurrentTransfers: Int,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = launchArguments(
            port: port,
            bandwidthLimit: bandwidthLimit,
            concurrentTransfers: concurrentTransfers
        )
        proc.environment = RcloneEnvironment.childEnvironment(base: baseEnvironment)
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        return proc
    }

    /// Explains an early rcd exit when the cause is a config Nimbus can't
    /// unlock. Runs off the main actor: it shells out to rclone and security.
    nonisolated private static func configLockedWithoutKey(binaryPath: String) async -> Bool {
        await Task.detached(priority: .utility) {
            ConfigEncryptionState.read(binaryPath: binaryPath) == .lockedWithoutKey
        }.value
    }

    /// Builds the rclone command line used for every daemon launch. The empty
    /// persisted bandwidth preference is intentionally represented as rclone's
    /// explicit `off` value, while transfer count is clamped to the UI range.
    static func launchArguments(
        port: Int,
        bandwidthLimit: String,
        concurrentTransfers: Int
    ) -> [String] {
        [
            "rcd",
            "--rc-no-auth",
            "--rc-addr", "127.0.0.1:\(port)",
            "--rc-allow-origin=*",
            "--rc-serve",
            "--bwlimit", bandwidthLimit.isEmpty ? "off" : bandwidthLimit,
            "--transfers", String(min(max(concurrentTransfers, 1), 32)),
        ]
    }

    /// A test or preview host never starts the real daemon or runs the
    /// stale-daemon cleanup. Tests that drive `start()` on purpose inject
    /// `TestStartupHooks`, which replace the cleanup and port probe.
    private var mayStartDaemon: Bool {
#if DEBUG
        if testStartupHooks != nil { return true }
#endif
        return LaunchContext.current.managesSystemProcesses
    }

    private func isCurrent(_ lifecycleID: UUID) -> Bool {
        self.lifecycleID == lifecycleID
    }

    private func waitForStaleDaemonCleanup() async {
        if staleDaemonCleanupTask == nil {
            staleDaemonCleanupTask = Task { [weak self] in
                guard let self else { return }
                await self.performStaleDaemonCleanup()
            }
        }
        await staleDaemonCleanupTask?.value
    }

    private func performStaleDaemonCleanup() async {
#if DEBUG
        if let cleanup = testStartupHooks?.staleDaemonCleanup {
            await cleanup()
            return
        }
#endif
        guard LaunchContext.current.managesSystemProcesses else { return }
        await Self.killStaleRcloneDaemons(in: Self.portRange, logger: logger)
    }

    private func findAvailablePort() async -> Int? {
#if DEBUG
        if let availablePort = testStartupHooks?.availablePort {
            return await availablePort()
        }
#endif
        return await Self.findAvailablePort(in: Self.portRange)
    }

    private func readRcloneVersion(at binaryPath: String) async -> String? {
#if DEBUG
        if let rcloneVersion = testStartupHooks?.rcloneVersion {
            return await rcloneVersion(binaryPath)
        }
#endif
        return await Self.rcloneVersion(at: binaryPath)
    }

    private func healthCheck() async -> Bool {
#if DEBUG
        if let healthCheck = testStartupHooks?.healthCheck {
            return await healthCheck()
        }
#endif
        return await client.healthCheck()
    }

    private var maximumHealthCheckAttempts: Int {
#if DEBUG
        testStartupHooks?.maxHealthCheckAttempts ?? 30
#else
        30
#endif
    }

    private func waitForHealthRetry() async {
#if DEBUG
        if let healthRetryDelay = testStartupHooks?.healthRetryDelay {
            await healthRetryDelay()
            return
        }
#endif
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// Kills any rclone rcd processes listening on ports in our range that were
    /// left over from previous app sessions.
    nonisolated private static func killStaleRcloneDaemons(in range: ClosedRange<Int>, logger: Logger) async {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            proc.arguments = ["-f", "rclone rcd"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

                for pid in pids {
                    kill(pid, SIGTERM)
                    logger.info("Killed stale rclone process: \(pid)")
                }

                // Brief pause to let ports free up
                if !pids.isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                // Non-fatal
            }
        }.value
    }

    nonisolated private static func findAvailablePort(in range: ClosedRange<Int>) async -> Int? {
        await Task.detached(priority: .userInitiated) {
            for port in range {
                if Self.isPortAvailable(port) {
                    return port
                }
            }
            return nil
        }.value
    }

    /// Runs outside the main actor because `waitUntilExit()` blocks.
    nonisolated private static func rcloneVersion(at binaryPath: String) async -> String? {
        await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binaryPath)
            proc.arguments = ["version"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { return nil }

                let output = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )
                return output?.split(whereSeparator: \.isNewline).first.map(String.init)
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
