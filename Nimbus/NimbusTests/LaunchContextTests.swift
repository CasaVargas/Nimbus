import Foundation
import Testing
@testable import Nimbus

@Suite("LaunchContext")
@MainActor
struct LaunchContextTests {
    @Test func plainEnvironmentIsANormalLaunch() {
        let context = LaunchContext.detect(
            environment: ["HOME": "/Users/someone", "XCODE_RUNNING_FOR_PREVIEWS": "0"],
            isXCTestLoaded: false
        )

        #expect(context == .normal)
        #expect(context.managesSystemProcesses)
    }

    @Test(arguments: ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"])
    func testEnvironmentKeyMarksATestHost(key: String) {
        let context = LaunchContext.detect(environment: [key: ""], isXCTestLoaded: false)

        #expect(context == .testHost)
        #expect(!context.managesSystemProcesses)
    }

    @Test func loadedXCTestMarksATestHost() {
        #expect(LaunchContext.detect(environment: [:], isXCTestLoaded: true) == .testHost)
    }

    @Test func previewFlagMarksAPreviewHost() {
        let context = LaunchContext.detect(
            environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"],
            isXCTestLoaded: false
        )

        #expect(context == .previewHost)
        #expect(!context.managesSystemProcesses)
    }

    /// The process running this test is the real test host.
    @Test func runningTestHostIsDetected() {
        #expect(LaunchContext.current == .testHost)
    }

    /// The environment alone must identify the host: `NimbusApp.bootstrap()`
    /// can run before XCTest is loaded into the process.
    @Test func runningTestHostIsDetectedFromEnvironmentAlone() {
        let context = LaunchContext.detect(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: false
        )

        #expect(context == .testHost)
    }

    /// `start()` without injected hooks is the production path. In a test
    /// host it must not run the binary (or the cleanup that precedes it).
    @Test func daemonDoesNotStartInATestHost() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nimbus-LaunchContextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("ran")
        let binary = directory.appendingPathComponent("rclone")
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)

        let daemon = RcloneDaemon()
        await daemon.start(binaryPath: binary.path)

        #expect(daemon.status == .idle)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
