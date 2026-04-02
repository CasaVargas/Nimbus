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
    let client: RcloneClient

    private var process: Process?
    private var healthTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "daemon")

    private static let portRange = 5572...5580

    init() {
        client = RcloneClient()
    }

    func start(binaryPath: String = "/usr/local/bin/rclone") async {
        guard status != .connected && status != .starting else { return }
        status = .starting

        guard let availablePort = await Self.findAvailablePort(in: Self.portRange) else {
            status = .error("No available port in range \(Self.portRange)")
            return
        }
        port = availablePort
        client.updatePort(availablePort)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "rcd",
            "--rc-no-auth",
            "--rc-addr", "127.0.0.1:\(availablePort)",
            "--rc-allow-origin=*",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
            logger.info("Started rclone on port \(availablePort), pid \(proc.processIdentifier)")
        } catch {
            status = .error("Failed to start rclone: \(error.localizedDescription)")
            return
        }

        let maxAttempts = 30
        for attempt in 1...maxAttempts {
            if await client.healthCheck() {
                status = .connected
                logger.info("Rclone healthy after \(attempt) attempts")
                return
            }
            if !proc.isRunning {
                status = .error("Rclone process exited unexpectedly")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        status = .error("Rclone failed to respond after \(maxAttempts) health checks")
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
            logger.info("Stopped rclone daemon")
        }
        process = nil
        status = .idle
    }

    func retry(binaryPath: String = "/usr/local/bin/rclone") async {
        stop()
        await start(binaryPath: binaryPath)
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
