import Foundation
import os

@MainActor
final class DiagnosticsService {
    struct Info: Sendable {
        let nimbusVersion: String
        let buildNumber: String
        let macOSVersion: String
        let architecture: String

        static var current: Self {
            Self(
                nimbusVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: Self.machineArchitecture()
            )
        }

        private static func machineArchitecture() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machine = systemInfo.machine
            let machineSize = MemoryLayout.size(ofValue: machine)
            return withUnsafePointer(to: machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: machineSize) {
                    String(cString: $0)
                }
            }
        }
    }

    private let info: Info
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "diagnostics")

    init(info: Info = .current) {
        self.info = info
    }

    /// Returns only fixed support fields. It intentionally omits all user data.
    func systemInformation(daemon: RcloneDaemon) -> String {
        [
            "Nimbus Version: \(info.nimbusVersion) (\(info.buildNumber))",
            "macOS Version: \(info.macOSVersion)",
            "Architecture: \(info.architecture)",
            "rclone Version: \(safeRcloneVersion(daemon.rcloneVersion))",
            "Daemon Status: \(safeDaemonStatus(daemon.status))",
            "Daemon Port: \(daemon.port)",
        ].joined(separator: "\n")
    }

    func openLogs() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-a", "Console",
            "--args",
            "--predicate", "subsystem == \"app.casavargas.nimbus\"",
        ]

        do {
            try process.run()
        } catch {
            logger.error("Unable to open Nimbus logs in Console")
        }
    }

    private func safeDaemonStatus(_ status: RcloneDaemon.Status) -> String {
        switch status {
        case .idle: "Not running"
        case .starting: "Starting"
        case .connected: "Connected"
        case .error: "Error"
        }
    }

    private func safeRcloneVersion(_ version: String?) -> String {
        guard let version else { return "Unknown" }
        let parts = version.split(separator: " ")
        guard
            parts.count == 2,
            parts[0] == "rclone",
            parts[1].first == "v",
            parts[1].count > 1,
            parts[1].dropFirst().unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || ".+-_".unicodeScalars.contains($0)
            })
        else {
            return "Unknown"
        }
        return version
    }
}
