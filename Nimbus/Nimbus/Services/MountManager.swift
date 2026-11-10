import FileProvider
import Foundation
import Observation
import os

/// Test-friendly summary of an `NSFileProviderDomain`. `MountManager.refreshAll()`
/// converts the OS type to this struct before passing to `reconcileFPDomains`
/// so the reconciliation logic can be unit-tested without spinning up FP.
struct FPDomainInfo: Equatable, Sendable {
    let identifier: String
    let displayName: String
}

/// Reconcile a snapshot of File Provider domains against the configured
/// `.fileProvider` mounts. Domains are registered under the bare remote
/// name (`MountConfig.remoteNameOnly` — see FileProviderBridge call sites),
/// so that, NOT `config.id`, is the matching key. Configs with a live
/// domain land in `mountedIDs`; configs whose domain vanished are dropped
/// from it and reported via `logger` (not auto-recreated — that's a
/// different flow). NFS configs are ignored entirely.
///
/// Pure function: testable without an `NSFileProviderManager` dependency.
func reconcileFPDomains(
    _ domains: [FPDomainInfo],
    configs: [MountConfig],
    mountedIDs: inout Set<String>,
    logger: (String) -> Void
) {
    for config in configs where config.backend == .fileProvider {
        if domains.contains(where: { $0.identifier == config.remoteNameOnly }) {
            mountedIDs.insert(config.id)
        } else {
            mountedIDs.remove(config.id)
            logger("FP config \(config.id) has no matching domain; not auto-recreating")
        }
    }
}

/// Extract the mount points of localhost NFS volumes from `/sbin/mount`
/// output, skipping any that this session currently owns. Pure function so
/// the sweep's targeting can be unit-tested — a previous version unmounted
/// the very volumes `restoreMounts` had just brought up.
func parseStaleMountPoints(mountOutput: String, excluding activeMountPoints: Set<String>) -> [String] {
    var stale: [String] = []
    for line in mountOutput.split(separator: "\n") {
        let lineStr = String(line)
        guard lineStr.contains("localhost"), lineStr.contains("nfs") else { continue }
        guard let onRange = lineStr.range(of: " on "),
              let parenRange = lineStr.range(of: " (", range: onRange.upperBound..<lineStr.endIndex)
        else { continue }
        let mountPoint = String(lineStr[onRange.upperBound..<parenRange.lowerBound])
        if !activeMountPoints.contains(mountPoint) {
            stale.append(mountPoint)
        }
    }
    return stale
}

/// Which configs to bring up at launch: every `.nfs` config flagged
/// "Mount at Launch", plus whatever was mounted when the app last quit —
/// so a reboot with launch-at-login restores the user's world unprompted.
/// `.fileProvider` configs are excluded; FP domains persist across restarts
/// on their own.
func configsToRestore(configs: [MountConfig], lastActiveIDs: Set<String>) -> [MountConfig] {
    configs.filter { $0.backend == .nfs && ($0.autoMount || lastActiveIDs.contains($0.id)) }
}

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

    /// IDs (`MountConfig.id`) currently considered mounted. Tracked separately
    /// from `activeMounts` so the UI can map config → state without re-deriving
    /// from `mountPoint` strings on every render.
    private(set) var mountedIDs: Set<String> = []

    /// IDs whose mount/unmount operation is in flight — used to drive the
    /// `.mounting` / `.unmounting` transitional `StatusToggleState`.
    private(set) var inFlight: Set<String> = []

    /// Per-config error messages from the last failed mount/unmount.
    private(set) var errors: [String: String] = [:]

    /// Timestamp of the last successful mount per config. Surfaced in
    /// `MountInspector`.
    private(set) var lastMounted: [String: Date] = [:]

    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "mount")
    private var healthTask: Task<Void, Never>?

    /// Path to the rclone binary used for `serve nfs`. Set from
    /// `AppSettings.rcloneBinaryPath` at startup so NFS serving resolves the
    /// same binary as the RC daemon (Homebrew on Apple silicon lives at
    /// /opt/homebrew/bin, not /usr/local/bin).
    var rcloneBinaryPath = "/usr/local/bin/rclone"

    /// Configs that have consumed their one automatic remount after their
    /// NFS server died. One attempt per config per session — a server that
    /// dies twice stays down until the user intervenes, instead of looping.
    private var remountAttempted: Set<String> = []

    /// True while `restoreMounts` is replaying launch mounts. Suppresses
    /// `persistLastActiveIDs` so a transient restore failure (network not up
    /// yet at login) doesn't erase the mount from the next launch's intent.
    private var isRestoring = false

    private static let nfsPortRange = 19049...19149
    private static let nfsHost = "localhost"
    private static let lastActiveIDsKey = "lastActiveMountIDs"

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
        nfsProcess.executableURL = URL(fileURLWithPath: rcloneBinaryPath)
        var args = ["serve", "nfs", remote, "--addr", "\(Self.nfsHost):\(nfsPort)"]
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

        let ready = await Self.waitForServerReady(port: nfsPort, timeout: 10.0)
        if !ready {
            nfsProcess.terminate()
            throw MountError.serverStartTimeout
        }

        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/sbin/mount_nfs")
        mountProcess.arguments = [
            "-o", "nfsvers=3,tcp,nolocks,noresvport,soft,timeo=50,nobrowse,nosuid,nodev,port=\(nfsPort),mountport=\(nfsPort)",
            "\(Self.nfsHost):/",
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

    // MARK: - Config-keyed wrappers

    /// Mount a `MountConfig`; tracks `inFlight`, `errors`, `mountedIDs`,
    /// and `lastMounted` by `config.id`. Wraps `mount(remote:mountPoint:readOnly:)`.
    func mountConfig(_ config: MountConfig) async throws {
        inFlight.insert(config.id)
        errors[config.id] = nil
        do {
            try await mount(
                remote: config.remote,
                mountPoint: config.mountPoint,
                readOnly: config.vfsMode == .readOnly
            )
            mountedIDs.insert(config.id)
            lastMounted[config.id] = Date()
            persistLastActiveIDs()
        } catch {
            errors[config.id] = error.localizedDescription
            inFlight.remove(config.id)
            throw error
        }
        inFlight.remove(config.id)
    }

    /// Unmount a `MountConfig`; tracks `inFlight`, `errors`, and `mountedIDs`
    /// by `config.id`. Wraps `unmount(mountPoint:)`.
    func unmountConfig(_ config: MountConfig) async throws {
        inFlight.insert(config.id)
        errors[config.id] = nil
        do {
            try await unmount(mountPoint: config.mountPoint)
            mountedIDs.remove(config.id)
            persistLastActiveIDs()
        } catch {
            errors[config.id] = error.localizedDescription
            inFlight.remove(config.id)
            throw error
        }
        inFlight.remove(config.id)
    }

    // MARK: - Launch restore

    /// Bring up launch-time mounts: user-flagged "Mount at Launch" configs
    /// plus whatever was mounted when the app last quit. Serial by design —
    /// each mount claims its port before the next port scan runs. Failures
    /// land in `errors` (surfaced by MountsView) rather than aborting the rest.
    func restoreMounts(configs: [MountConfig]) async {
        let candidates = configsToRestore(
            configs: configs,
            lastActiveIDs: Self.loadLastActiveIDs()
        )
        guard !candidates.isEmpty else { return }
        isRestoring = true
        defer { isRestoring = false }
        for config in candidates where !mountedIDs.contains(config.id) {
            do {
                try await mountConfig(config)
            } catch {
                logger.error("Launch restore failed for \(config.id): \(error.localizedDescription)")
            }
        }
    }

    /// IDs of NFS mounts that were up when the app last ran. Written on every
    /// user-driven mount/unmount; deliberately NOT written by `stopAll` (quit
    /// unmounts everything, but the next launch should bring it all back).
    static func loadLastActiveIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: lastActiveIDsKey) ?? [])
    }

    private func persistLastActiveIDs() {
        guard !isRestoring else { return }
        UserDefaults.standard.set(Array(mountedIDs).sorted(), forKey: Self.lastActiveIDsKey)
    }

    func refreshAll() async {
        await cleanupStaleMounts()
        await reconcileFileProviderDomains()
    }

    private func reconcileFileProviderDomains() async {
        let nsDomains: [NSFileProviderDomain]
        do {
            nsDomains = try await NSFileProviderManager.domains()
        } catch {
            logger.warning("refreshAll: getDomains failed: \(FileProviderErrorText.describe(error), privacy: .public)")
            return
        }
        let domainInfos = nsDomains.map {
            FPDomainInfo(identifier: $0.identifier.rawValue, displayName: $0.displayName)
        }
        // configStore isn't directly accessible from MountManager; refreshAll
        // is called by callers that have a MountConfigStore in scope. Pass
        // configs explicitly via the configs storage on this MountManager.
        reconcileFPDomains(domainInfos, configs: configs, mountedIDs: &mountedIDs) { msg in
            logger.info("\(msg)")
        }
    }

    /// Set of configs `refreshAll()` should reconcile against. The caller
    /// updates this just before calling `refreshAll()`. Done this way to
    /// keep `MountManager` independent of `MountConfigStore` (which would
    /// otherwise create an env/store coupling).
    var configs: [MountConfig] = []

    func startHealthMonitor() {
        healthTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self.checkHealth()
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
        // A test or preview host owns no mounts, so every mount and NFS
        // server it can see belongs to another running copy of the app.
        guard LaunchContext.current.managesSystemProcesses else { return }
        await killOrphanServeProcesses()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let stale = parseStaleMountPoints(
                mountOutput: output,
                excluding: Set(activeMounts.map(\.mountPoint))
            )
            for mountPoint in stale {
                logger.info("Cleaning stale mount: \(mountPoint)")
                let forceProcess = Process()
                forceProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                forceProcess.arguments = ["unmount", "force", mountPoint]
                forceProcess.standardOutput = FileHandle.nullDevice
                forceProcess.standardError = FileHandle.nullDevice
                try? forceProcess.run()
                forceProcess.waitUntilExit()
            }
        } catch {
            logger.error("Failed to check for stale mounts: \(error)")
        }
    }

    /// SIGTERM any `rclone serve nfs` processes this session doesn't own.
    /// Orphans from a crashed session keep listening in our port range; a
    /// new mount that picked the same port would pass the readiness probe
    /// against the orphan and hand mount_nfs someone else's filesystem.
    private func killOrphanServeProcesses() async {
        let ownedPIDs = Set(nfsProcesses.values.map(\.processIdentifier))
        let log = logger
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            proc.arguments = ["-f", "rclone serve nfs"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let pids = output.split(separator: "\n")
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !ownedPIDs.contains($0) }

                for pid in pids {
                    kill(pid, SIGTERM)
                    log.info("Killed orphan NFS server process: \(pid)")
                }
                if !pids.isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                // Non-fatal — the port probe in findAvailableNfsPort still
                // steers new mounts away from any survivor.
            }
        }.value
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

            // Keep the UI truthful: the volume is gone, so the config is no
            // longer mounted. One automatic remount per config per session;
            // after that the error badge stands until the user acts.
            guard let config = configs.first(where: { $0.mountPoint == mountPoint }) else { continue }
            mountedIDs.remove(config.id)
            errors[config.id] = "NFS server exited unexpectedly"
            if !remountAttempted.contains(config.id) {
                remountAttempted.insert(config.id)
                logger.info("Attempting automatic remount of \(config.id)")
                Task { try? await self.mountConfig(config) }
            }
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
            if !usedPorts.contains(port) && Self.isPortFree(port) {
                return port
            }
        }
        return nil
    }

    /// Bind-probe: a port a leftover process is still listening on is not
    /// ours to hand to a new `rclone serve nfs`.
    nonisolated private static func isPortFree(_ port: Int) -> Bool {
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

    /// Waits for NFS server to accept connections, using exponential backoff.
    nonisolated private static func waitForServerReady(port: Int, timeout: TimeInterval) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(timeout)
            var delay: UInt64 = 50_000_000 // 50ms in nanoseconds
            let maxDelay: UInt64 = 1_000_000_000 // 1 second cap

            while Date() < deadline {
                let socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD >= 0 else {
                    try? await Task.sleep(nanoseconds: delay)
                    delay = min(delay + delay / 2, maxDelay)
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
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay + delay / 2, maxDelay)
            }
            return false
        }.value
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
