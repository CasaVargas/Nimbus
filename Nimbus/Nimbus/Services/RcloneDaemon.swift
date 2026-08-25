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
    private var hasCleanedStaleDaemons = false
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "daemon")

    private static let portRange = 5572...5580

    init() {
        client = RcloneClient()
    }

#if DEBUG
    /// Test fixture initializer. It is excluded from release builds.
    init(
        testStatus: Status,
        activeBinaryPath: String? = nil,
        rcloneVersion: String? = nil,
        port: Int = 5572
    ) {
        client = RcloneClient()
        status = testStatus
        self.activeBinaryPath = activeBinaryPath
        self.rcloneVersion = rcloneVersion
        self.port = port
    }
#endif

    func start(binaryPath: String = "/usr/local/bin/rclone") async {
        guard status != .connected && status != .starting else { return }
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        status = .starting

        // Kill any stale rclone daemons from previous app sessions
        if !hasCleanedStaleDaemons {
            hasCleanedStaleDaemons = true
            await Self.killStaleRcloneDaemons(in: Self.portRange, logger: logger)
            guard isCurrent(lifecycleID) else { return }
        }

        guard let availablePort = await Self.findAvailablePort(in: Self.portRange) else {
            guard isCurrent(lifecycleID) else { return }
            status = .error("No available port in range \(Self.portRange)")
            return
        }
        guard isCurrent(lifecycleID) else { return }
        port = availablePort
        client.updatePort(availablePort)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "rcd",
            "--rc-no-auth",
            "--rc-addr", "127.0.0.1:\(availablePort)",
            "--rc-allow-origin=*",
            // Serve remote objects at GET /[remote:]/path — the RC API has
            // no download method (operations/cat does not exist), so this
            // flag IS the download path for RcloneClient.downloadFile and
            // therefore for File Provider materialization.
            "--rc-serve",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

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

        let version = await Self.rcloneVersion(at: binaryPath)
        guard isCurrent(lifecycleID) else { return }
        rcloneVersion = version

        let maxAttempts = 30
        for attempt in 1...maxAttempts {
            if await client.healthCheck() {
                guard isCurrent(lifecycleID) else { return }
                status = .connected
                logger.info("Rclone healthy after \(attempt) attempts")
                return
            }
            guard isCurrent(lifecycleID) else { return }
            if !proc.isRunning {
                status = .error("Rclone process exited unexpectedly")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

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

    func retry(binaryPath: String = "/usr/local/bin/rclone") async {
        await restart(binaryPath: binaryPath)
    }

    func restartRequired(for configuredPath: String) -> Bool {
        status == .connected && activeBinaryPath != configuredPath
    }

    func restart(binaryPath: String) async {
        stop()
        await start(binaryPath: binaryPath)
    }

    private func isCurrent(_ lifecycleID: UUID) -> Bool {
        self.lifecycleID == lifecycleID
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
