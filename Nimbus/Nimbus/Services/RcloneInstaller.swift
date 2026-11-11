import CryptoKit
import Darwin
import Foundation
import Observation
import os

/// The CPU flavour of an official rclone macOS build.
enum RcloneArch: String, Sendable, Equatable {
    case arm64
    case amd64

    static func forHardware(isArm64: Bool) -> RcloneArch {
        isArm64 ? .arm64 : .amd64
    }

    /// Decided from the hardware, not the slice Nimbus runs as: a Nimbus
    /// under Rosetta still gets the native arm64 rclone.
    static var current: RcloneArch {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let found = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0
        return forHardware(isArm64: found && value == 1)
    }
}

/// One official rclone release for one architecture, and where its files live.
struct RcloneRelease: Equatable, Sendable {
    let version: String
    let arch: RcloneArch

    static let versionURL = URL(string: "https://downloads.rclone.org/version.txt")!

    /// Reads `rclone v1.76.0` (rclone.org's `version.txt`, or the first line
    /// of `rclone version`) as `1.76.0`. Anything else is nil.
    static func parseVersion(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("rclone v") else { return nil }
        let version = String(trimmed.dropFirst("rclone v".count))
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        return version
    }

    /// True when `candidate` is a later version than `installed`.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = installed.split(separator: ".").map { Int($0) ?? 0 }
        return rhs.lexicographicallyPrecedes(lhs)
    }

    var folderName: String { "rclone-v\(version)-osx-\(arch.rawValue)" }
    var archiveName: String { "\(folderName).zip" }

    var archiveURL: URL {
        URL(string: "https://downloads.rclone.org/v\(version)/\(archiveName)")!
    }

    /// Two independent hosts publish the same checksums; both must agree.
    var checksumURLs: [URL] {
        [
            URL(string: "https://downloads.rclone.org/v\(version)/SHA256SUMS")!,
            URL(string: "https://github.com/rclone/rclone/releases/download/v\(version)/SHA256SUMS")!,
        ]
    }
}

/// rclone's `SHA256SUMS`: `<64 hex>  <file name>` lines inside a PGP
/// clear-signed wrapper. The wrapper is skipped; the signature is not checked
/// (see docs/superpowers/specs/2026-11-11-rclone-download-design.md).
enum RcloneChecksums {
    /// File name → lowercase hex digest. Lines that aren't a checksum line
    /// (armour, headers, the signature block, blanks) are ignored.
    static func parse(_ text: String) -> [String: String] {
        var sums: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let hash = parts[0].lowercased()
            var name = String(parts[1])
            if name.hasPrefix("*") { name.removeFirst() } // binary-mode marker
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            sums[name] = hash
        }
        return sums
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Passes only when every list names `fileName` and every list's digest
    /// matches `data`.
    static func verify(_ data: Data, fileName: String, against lists: [[String: String]]) -> Bool {
        guard !lists.isEmpty else { return false }
        let actual = sha256Hex(of: data)
        return lists.allSatisfy { $0[fileName] == actual }
    }
}

/// Downloads, verifies and installs the official rclone build into a folder
/// Nimbus owns. Only runs when the person asks for it.
@Observable
@MainActor
final class RcloneInstaller {
    enum Phase: Equatable {
        case idle
        case checking
        case downloading(version: String)
        case verifying
        case installing
        case installed(version: String)
        case upToDate(version: String)
        case failed(Failure)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .verifying, .installing: true
            default: false
            }
        }
    }

    enum Failure: Error, Equatable {
        case network
        case unexpectedVersion
        case checksumMismatch
        case install(String)
        case wontRun

        var message: String {
            switch self {
            case .network:
                "Couldn't reach rclone.org. Check your connection and try again."
            case .unexpectedVersion:
                "rclone.org returned an unexpected version."
            case .checksumMismatch:
                "The download didn't match rclone's published checksum, so it wasn't installed."
            case .install(let reason):
                "Couldn't install rclone: \(reason)"
            case .wontRun:
                "The downloaded rclone didn't run."
            }
        }
    }

    /// Network access, injectable so tests never go online.
    struct Network: Sendable {
        let fetch: @Sendable (URL) async throws -> Data

        static let live = Network { url in
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    private(set) var phase: Phase = .idle

    let installDirectory: URL
    private let network: Network
    private let arch: RcloneArch
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "rclone-installer")

    nonisolated static var defaultInstallDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus", isDirectory: true)
            .appendingPathComponent("rclone", isDirectory: true)
    }

    /// Where the Nimbus-managed rclone lives.
    nonisolated static var managedBinaryPath: String {
        defaultInstallDirectory.appendingPathComponent("rclone").path
    }

    var binaryURL: URL { installDirectory.appendingPathComponent("rclone") }

    init(
        network: Network = .live,
        installDirectory: URL = RcloneInstaller.defaultInstallDirectory,
        arch: RcloneArch = .current
    ) {
        self.network = network
        self.installDirectory = installDirectory
        self.arch = arch
    }

    /// Clears a finished or failed attempt, e.g. after rclone turned up
    /// somewhere else.
    func reset() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    /// The newest version rclone.org publishes.
    func latestVersion() async throws(Failure) -> String {
        let data: Data
        do {
            data = try await network.fetch(RcloneRelease.versionURL)
        } catch {
            throw .network
        }
        guard let text = String(data: data, encoding: .utf8),
              let version = RcloneRelease.parseVersion(text) else {
            throw .unexpectedVersion
        }
        return version
    }

    /// Installs the latest release. Returns the binary path on success; on
    /// failure `phase` says why and any earlier install is left untouched.
    @discardableResult
    func install() async -> String? {
        guard !phase.isBusy else { return nil }
        phase = .checking
        do {
            let version = try await latestVersion()
            try await install(RcloneRelease(version: version, arch: arch))
            phase = .installed(version: version)
            return binaryURL.path
        } catch {
            logger.error("rclone install failed: \(String(describing: error), privacy: .public)")
            phase = .failed(error)
            return nil
        }
    }

    /// Installs a newer release only if one exists. Returns the binary path
    /// when it installed something.
    @discardableResult
    func update(installedVersion: String?) async -> String? {
        guard !phase.isBusy else { return nil }
        phase = .checking
        do {
            let latest = try await latestVersion()
            if let installedVersion, !RcloneRelease.isNewer(latest, than: installedVersion) {
                phase = .upToDate(version: installedVersion)
                return nil
            }
            try await install(RcloneRelease(version: latest, arch: arch))
            phase = .installed(version: latest)
            return binaryURL.path
        } catch {
            logger.error("rclone update failed: \(String(describing: error), privacy: .public)")
            phase = .failed(error)
            return nil
        }
    }

    private func install(_ release: RcloneRelease) async throws(Failure) {
        phase = .downloading(version: release.version)
        let archive: Data
        var lists: [[String: String]] = []
        do {
            archive = try await network.fetch(release.archiveURL)
            for url in release.checksumURLs {
                let data = try await network.fetch(url)
                lists.append(RcloneChecksums.parse(String(decoding: data, as: UTF8.self)))
            }
        } catch {
            throw .network
        }

        phase = .verifying
        let fileName = release.archiveName
        let verified = await Task.detached(priority: .userInitiated) {
            RcloneChecksums.verify(archive, fileName: fileName, against: lists)
        }.value
        guard verified else { throw .checksumMismatch }

        phase = .installing
        let destination = installDirectory
        let outcome = await Task.detached(priority: .userInitiated) {
            Self.unpackAndInstall(archive: archive, release: release, into: destination)
        }.value
        if case .failure(let failure) = outcome { throw failure }
    }

    /// Unzips into a temporary folder, checks the binary runs and reports the
    /// expected version, then moves it into place in one step.
    nonisolated private static func unpackAndInstall(
        archive: Data,
        release: RcloneRelease,
        into destination: URL
    ) -> Result<Void, Failure> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("nimbus-rclone-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(release.archiveName)
            try archive.write(to: zip)
            let unpacked = work.appendingPathComponent("unpacked")
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]).status == 0 else {
                return .failure(.install("the download couldn't be unpacked."))
            }
            let binary = unpacked.appendingPathComponent(release.folderName).appendingPathComponent("rclone")
            guard fm.fileExists(atPath: binary.path) else {
                return .failure(.install("the download has no rclone in it."))
            }
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            // URLSession writes aren't quarantined, but be sure: the binary is
            // ad-hoc signed and not notarised, so Gatekeeper would block it.
            removexattr(binary.path, "com.apple.quarantine", 0)

            let probe = run(binary.path, ["version"])
            guard probe.status == 0, RcloneRelease.parseVersion(probe.output) == release.version else {
                return .failure(.wontRun)
            }

            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent("rclone")
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: binary)
            } else {
                try fm.moveItem(at: binary, to: target)
            }
            return .success(())
        } catch {
            return .failure(.install(error.localizedDescription))
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "")
        }
    }
}
