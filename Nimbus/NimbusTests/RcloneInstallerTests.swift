import Foundation
import Testing
@testable import Nimbus

@Suite("RcloneRelease")
struct RcloneReleaseTests {
    @Test func parsesVersionTxt() {
        #expect(RcloneRelease.parseVersion("rclone v1.76.0\n") == "1.76.0")
        #expect(RcloneRelease.parseVersion("rclone v1.76.0") == "1.76.0")
    }

    @Test func parsesFirstLineOfRcloneVersionOutput() {
        let output = "rclone v1.75.2\n- os/version: darwin 27.2 (64 bit)\n- go/version: go1.25\n"
        #expect(RcloneRelease.parseVersion(output) == "1.75.2")
    }

    @Test(arguments: ["", "rclone", "rclone v1.76", "rclone v1.76.0-beta.1", "rclone vX.Y.Z", "<html>", "v1.76.0"])
    func rejectsUnexpectedVersionText(_ text: String) {
        #expect(RcloneRelease.parseVersion(text) == nil)
    }

    @Test func comparesVersions() {
        #expect(RcloneRelease.isNewer("1.77.0", than: "1.76.0"))
        #expect(RcloneRelease.isNewer("1.76.10", than: "1.76.9"))
        #expect(RcloneRelease.isNewer("2.0.0", than: "1.99.99"))
        #expect(!RcloneRelease.isNewer("1.76.0", than: "1.76.0"))
        #expect(!RcloneRelease.isNewer("1.75.2", than: "1.76.0"))
    }

    @Test func picksArchFromHardware() {
        #expect(RcloneArch.forHardware(isArm64: true) == .arm64)
        #expect(RcloneArch.forHardware(isArm64: false) == .amd64)
    }

    @Test func buildsArm64URLs() {
        let release = RcloneRelease(version: "1.76.0", arch: .arm64)
        #expect(release.archiveName == "rclone-v1.76.0-osx-arm64.zip")
        #expect(release.archiveURL.absoluteString
            == "https://downloads.rclone.org/v1.76.0/rclone-v1.76.0-osx-arm64.zip")
        #expect(release.checksumURLs.map(\.absoluteString) == [
            "https://downloads.rclone.org/v1.76.0/SHA256SUMS",
            "https://github.com/rclone/rclone/releases/download/v1.76.0/SHA256SUMS",
        ])
    }

    @Test func buildsAmd64URLs() {
        let release = RcloneRelease(version: "1.75.2", arch: .amd64)
        #expect(release.archiveURL.absoluteString
            == "https://downloads.rclone.org/v1.75.2/rclone-v1.75.2-osx-amd64.zip")
        #expect(release.folderName == "rclone-v1.75.2-osx-amd64")
    }

    @Test func everyURLIsHTTPS() {
        let release = RcloneRelease(version: "1.76.0", arch: .arm64)
        let urls = [RcloneRelease.versionURL, release.archiveURL] + release.checksumURLs
        #expect(urls.allSatisfy { $0.scheme == "https" })
    }
}

@Suite("RcloneChecksums")
struct RcloneChecksumsTests {
    static let arm = "e72dc90b70f4947a7b72b61bde4a4fbba5777b2874fb448951ffdde67ebd0ab7"
    static let amd = "4f5835733d52b818340f97b1fc0348a70461534d123363a183ca2b660219595a"

    static let signed = """
    -----BEGIN PGP SIGNED MESSAGE-----
    Hash: SHA1

    \(amd)  rclone-v1.76.0-osx-amd64.zip
    \(arm)  rclone-v1.76.0-osx-arm64.zip
    not a checksum line
    abc123  rclone-v1.76.0-short.zip
    -----BEGIN PGP SIGNATURE-----

    iQEzBAEBCAAdFiEE...
    -----END PGP SIGNATURE-----
    """

    @Test func parsesClearSignedFile() {
        let sums = RcloneChecksums.parse(Self.signed)
        #expect(sums["rclone-v1.76.0-osx-arm64.zip"] == Self.arm)
        #expect(sums["rclone-v1.76.0-osx-amd64.zip"] == Self.amd)
        #expect(sums.count == 2)
    }

    @Test func parsesCRLFUppercaseAndBinaryMarker() {
        let text = "\(Self.arm.uppercased())  rclone-v1.76.0-osx-arm64.zip\r\n\(Self.amd) *rclone-v1.76.0-osx-amd64.zip\r\n"
        let sums = RcloneChecksums.parse(text)
        #expect(sums["rclone-v1.76.0-osx-arm64.zip"] == Self.arm)
        #expect(sums["rclone-v1.76.0-osx-amd64.zip"] == Self.amd)
    }

    @Test func hashesData() {
        // SHA-256 of "abc", from FIPS 180-2.
        #expect(RcloneChecksums.sha256Hex(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func verifiesWhenEveryListAgrees() {
        let data = Data("abc".utf8)
        let sums = ["a.zip": RcloneChecksums.sha256Hex(of: data)]
        #expect(RcloneChecksums.verify(data, fileName: "a.zip", against: [sums, sums]))
    }

    @Test func failsWhenOneListDisagrees() {
        let data = Data("abc".utf8)
        let good = ["a.zip": RcloneChecksums.sha256Hex(of: data)]
        let bad = ["a.zip": String(repeating: "0", count: 64)]
        #expect(!RcloneChecksums.verify(data, fileName: "a.zip", against: [good, bad]))
    }

    @Test func failsWhenFileIsMissingOrNoLists() {
        let data = Data("abc".utf8)
        let good = ["a.zip": RcloneChecksums.sha256Hex(of: data)]
        #expect(!RcloneChecksums.verify(data, fileName: "b.zip", against: [good, good]))
        #expect(!RcloneChecksums.verify(data, fileName: "a.zip", against: [good, [:]]))
        #expect(!RcloneChecksums.verify(data, fileName: "a.zip", against: []))
    }
}

@Suite("RcloneInstaller")
@MainActor
struct RcloneInstallerTests {
    /// A fake release: a zip holding a shell script that answers
    /// `rclone version` like the real binary.
    struct FakeRelease {
        let version: String
        let archive: Data
        let release: RcloneRelease

        init(version: String, reportedVersion: String? = nil) throws {
            self.version = version
            release = RcloneRelease(version: version, arch: .arm64)
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("fake-rclone-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: work) }
            let folder = work.appendingPathComponent(release.folderName)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let script = folder.appendingPathComponent("rclone")
            try "#!/bin/sh\necho 'rclone v\(reportedVersion ?? version)'\n".write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let zip = work.appendingPathComponent(release.archiveName)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
            try proc.run()
            proc.waitUntilExit()
            archive = try Data(contentsOf: zip)
        }

        var sums: Data {
            Data("\(RcloneChecksums.sha256Hex(of: archive))  \(release.archiveName)\n".utf8)
        }

        func responses(checksums: [Data]? = nil) -> [URL: Data] {
            let lists = checksums ?? [sums, sums]
            var map: [URL: Data] = [
                RcloneRelease.versionURL: Data("rclone v\(version)\n".utf8),
                release.archiveURL: archive,
            ]
            for (url, data) in zip(release.checksumURLs, lists) { map[url] = data }
            return map
        }
    }

    static func network(_ responses: [URL: Data]) -> RcloneInstaller.Network {
        RcloneInstaller.Network { url in
            guard let data = responses[url] else { throw URLError(.notConnectedToInternet) }
            return data
        }
    }

    static func tempInstallDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nimbus-install-\(UUID().uuidString)")
    }

    @Test func installsVerifiedRelease() async throws {
        let fake = try FakeRelease(version: "1.76.0")
        let dir = Self.tempInstallDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = RcloneInstaller(network: Self.network(fake.responses()), installDirectory: dir, arch: .arm64)

        let path = await installer.install()

        #expect(path == dir.appendingPathComponent("rclone").path)
        #expect(installer.phase == .installed(version: "1.76.0"))
        #expect(FileManager.default.isExecutableFile(atPath: try #require(path)))
    }

    @Test func refusesChecksumMismatchAndKeepsOldBinary() async throws {
        let fake = try FakeRelease(version: "1.76.0")
        let dir = Self.tempInstallDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("rclone")
        try "old".write(to: old, atomically: true, encoding: .utf8)
        let wrong = Data("\(String(repeating: "0", count: 64))  \(fake.release.archiveName)\n".utf8)
        let installer = RcloneInstaller(
            network: Self.network(fake.responses(checksums: [fake.sums, wrong])),
            installDirectory: dir, arch: .arm64
        )

        let path = await installer.install()

        #expect(path == nil)
        #expect(installer.phase == .failed(.checksumMismatch))
        #expect(try String(contentsOf: old, encoding: .utf8) == "old")
    }

    @Test func reportsOffline() async {
        let installer = RcloneInstaller(network: Self.network([:]), installDirectory: Self.tempInstallDirectory(), arch: .arm64)
        #expect(await installer.install() == nil)
        #expect(installer.phase == .failed(.network))
    }

    @Test func reportsUnexpectedVersion() async {
        let installer = RcloneInstaller(
            network: Self.network([RcloneRelease.versionURL: Data("<html>404</html>".utf8)]),
            installDirectory: Self.tempInstallDirectory(), arch: .arm64
        )
        #expect(await installer.install() == nil)
        #expect(installer.phase == .failed(.unexpectedVersion))
    }

    @Test func rejectsBinaryReportingWrongVersion() async throws {
        let fake = try FakeRelease(version: "1.76.0", reportedVersion: "1.0.0")
        let dir = Self.tempInstallDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = RcloneInstaller(network: Self.network(fake.responses()), installDirectory: dir, arch: .arm64)

        #expect(await installer.install() == nil)
        #expect(installer.phase == .failed(.wontRun))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("rclone").path))
    }

    @Test func updateSkipsWhenCurrent() async throws {
        let fake = try FakeRelease(version: "1.76.0")
        let installer = RcloneInstaller(network: Self.network(fake.responses()), installDirectory: Self.tempInstallDirectory(), arch: .arm64)
        #expect(await installer.update(installedVersion: "1.76.0") == nil)
        #expect(installer.phase == .upToDate(version: "1.76.0"))
    }

    @Test func updateReplacesOlderInstall() async throws {
        let fake = try FakeRelease(version: "1.77.0")
        let dir = Self.tempInstallDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "old".write(to: dir.appendingPathComponent("rclone"), atomically: true, encoding: .utf8)
        let installer = RcloneInstaller(network: Self.network(fake.responses()), installDirectory: dir, arch: .arm64)

        let path = await installer.update(installedVersion: "1.76.0")

        #expect(installer.phase == .installed(version: "1.77.0"))
        let contents = try String(contentsOf: URL(fileURLWithPath: try #require(path)), encoding: .utf8)
        #expect(contents.contains("rclone v1.77.0"))
    }
}

@Suite("AppSettings.locateRclone")
struct RcloneLocatorTests {
    @Test func prefersHomebrewOverDownloadedCopy() {
        let present: Set = ["/opt/homebrew/bin/rclone", RcloneInstaller.managedBinaryPath]
        #expect(AppSettings.locateRclone(isExecutable: present.contains) == "/opt/homebrew/bin/rclone")
    }

    @Test func fallsBackToDownloadedCopy() {
        let present: Set = [RcloneInstaller.managedBinaryPath]
        #expect(AppSettings.locateRclone(isExecutable: present.contains) == RcloneInstaller.managedBinaryPath)
    }

    @Test func managedCopyLivesInApplicationSupport() {
        #expect(RcloneInstaller.managedBinaryPath.hasSuffix("/Library/Application Support/Nimbus/rclone/rclone"))
    }

    @Test func nilWhenNothingIsInstalled() {
        #expect(AppSettings.locateRclone(isExecutable: { _ in false }) == nil)
    }
}
