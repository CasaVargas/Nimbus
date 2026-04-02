import Foundation
import Observation
import os

struct ActiveMount: Identifiable, Sendable {
    let id: String
    let remote: String
    let mountPoint: String
    let port: Int
}

@Observable
@MainActor
final class MountManager {
    private(set) var activeMounts: [ActiveMount] = []
    private var nfsProcesses: [String: Process] = [:]

    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "mount")
    private var healthTask: Task<Void, Never>?

    private static let nfsPortRange = 19049...19149

    func mount(remote: String, mountPoint: String, readOnly: Bool) async throws {
        try validateMountPoint(mountPoint)
        try validateRemote(remote)

        guard let nfsPort = findAvailableNfsPort() else {
            throw MountError.noAvailablePort
        }

        try FileManager.default.createDirectory(
            atPath: mountPoint,
            withIntermediateDirectories: true
        )

        let nfsProcess = Process()
        nfsProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/rclone")
        var args = ["serve", "nfs", remote, "--addr", "localhost:\(nfsPort)"]
        if readOnly {
            args.append("--read-only")
        } else {
            args.append(contentsOf: ["--vfs-cache-mode", "writes"])
        }
        nfsProcess.arguments = args
        nfsProcess.standardOutput = FileHandle.nullDevice
        nfsProcess.standardError = FileHandle.nullDevice

        try nfsProcess.run()
        logger.info("Spawned NFS server for \(remote) on port \(nfsPort)")

        let ready = await waitForServerReady(port: nfsPort, timeout: 10.0)
        if !ready {
            nfsProcess.terminate()
            throw MountError.serverStartTimeout
        }

        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/sbin/mount_nfs")
        mountProcess.arguments = [
            "-o", "nfsvers=3,tcp,nolocks,noresvport,soft,timeo=50,nobrowse,nosuid,nodev,port=\(nfsPort),mountport=\(nfsPort)",
            "localhost:/",
            mountPoint,
        ]

        let pipe = Pipe()
        mountProcess.standardError = pipe
        mountProcess.standardOutput = FileHandle.nullDevice

        try mountProcess.run()
        mountProcess.waitUntilExit()

        if mountProcess.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "unknown error"
            nfsProcess.terminate()
            throw MountError.mountFailed(errorMessage)
        }

        let mount = ActiveMount(
            id: mountPoint,
            remote: remote,
            mountPoint: mountPoint,
            port: nfsPort
        )
        activeMounts.append(mount)
        nfsProcesses[mountPoint] = nfsProcess
        logger.info("Mounted \(remote) at \(mountPoint)")
    }

    func unmount(mountPoint: String) async throws {
        let umountProcess = Process()
        umountProcess.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umountProcess.arguments = [mountPoint]
        umountProcess.standardOutput = FileHandle.nullDevice
        umountProcess.standardError = FileHandle.nullDevice

        try umountProcess.run()

        let completed = await waitForProcess(umountProcess, timeout: 5.0)
        if !completed || umountProcess.terminationStatus != 0 {
            logger.warning("umount timed out, force unmounting \(mountPoint)")
            let forceProcess = Process()
            forceProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            forceProcess.arguments = ["unmount", "force", mountPoint]
            forceProcess.standardOutput = FileHandle.nullDevice
            forceProcess.standardError = FileHandle.nullDevice
            try forceProcess.run()
            forceProcess.waitUntilExit()
        }

        if let nfsProcess = nfsProcesses[mountPoint] {
            if nfsProcess.isRunning {
                nfsProcess.terminate()
                nfsProcess.waitUntilExit()
            }
            nfsProcesses.removeValue(forKey: mountPoint)
        }

        activeMounts.removeAll { $0.mountPoint == mountPoint }
        logger.info("Unmounted \(mountPoint)")
    }

    func startHealthMonitor() {
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.checkHealth()
            }
        }
    }

    func stopAll() async {
        healthTask?.cancel()
        healthTask = nil

        for mount in activeMounts {
            try? await unmount(mountPoint: mount.mountPoint)
        }
    }

    func cleanupStaleMounts() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.split(separator: "\n") {
                let lineStr = String(line)
                if lineStr.contains("localhost") && lineStr.contains("nfs") {
                    if let onRange = lineStr.range(of: " on "),
                       let parenRange = lineStr.range(of: " (", range: onRange.upperBound..<lineStr.endIndex) {
                        let mountPoint = String(lineStr[onRange.upperBound..<parenRange.lowerBound])
                        logger.info("Cleaning stale mount: \(mountPoint)")
                        let forceProcess = Process()
                        forceProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                        forceProcess.arguments = ["unmount", "force", mountPoint]
                        forceProcess.standardOutput = FileHandle.nullDevice
                        forceProcess.standardError = FileHandle.nullDevice
                        try? forceProcess.run()
                        forceProcess.waitUntilExit()
                    }
                }
            }
        } catch {
            logger.error("Failed to check for stale mounts: \(error)")
        }
    }

    // MARK: - Private

    private func checkHealth() {
        var deadMounts: [String] = []

        for (mountPoint, process) in nfsProcesses {
            if !process.isRunning {
                logger.warning("NFS server for \(mountPoint) died")
                deadMounts.append(mountPoint)
            }
        }

        for mountPoint in deadMounts {
            nfsProcesses.removeValue(forKey: mountPoint)
            activeMounts.removeAll { $0.mountPoint == mountPoint }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            proc.arguments = ["unmount", "force", mountPoint]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func validateMountPoint(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw MountError.invalidMountPoint("Must be an absolute path")
        }
        guard !path.contains("..") else {
            throw MountError.invalidMountPoint("Must not contain '..'")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else {
            throw MountError.invalidMountPoint("Must be under home directory")
        }
    }

    private func validateRemote(_ remote: String) throws {
        let pattern = /^[\w\s-]+:.*$/
        guard remote.wholeMatch(of: pattern) != nil else {
            throw MountError.invalidRemote("Invalid remote format: \(remote)")
        }
    }

    private func findAvailableNfsPort() -> Int? {
        let usedPorts = Set(activeMounts.map(\.port))
        for port in Self.nfsPortRange {
            if !usedPorts.contains(port) {
                return port
            }
        }
        return nil
    }

    private func waitForServerReady(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            guard socketFD >= 0 else {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }
            defer { close(socketFD) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if result == 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func waitForProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && process.isRunning {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return !process.isRunning
    }
}

enum MountError: Error, LocalizedError {
    case invalidMountPoint(String)
    case invalidRemote(String)
    case noAvailablePort
    case serverStartTimeout
    case mountFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMountPoint(let msg): "Invalid mount point: \(msg)"
        case .invalidRemote(let msg): "Invalid remote: \(msg)"
        case .noAvailablePort: "No available NFS port"
        case .serverStartTimeout: "NFS server failed to start within timeout"
        case .mountFailed(let msg): "Mount failed: \(msg)"
        }
    }
}
