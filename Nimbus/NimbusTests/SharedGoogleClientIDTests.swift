import Foundation
import RcloneKit
import SwiftUI
import Testing

@testable import Nimbus

@Suite("Shared Google client ID")
@MainActor
struct SharedGoogleClientIDTests {
    @Test func onlyDriveWithoutItsOwnCredentialsCounts() {
        #expect(SharedGoogleClientID.isUsed(type: "drive", config: [:]))
        #expect(SharedGoogleClientID.isUsed(type: "drive", config: ["client_id": "  "]))
        #expect(!SharedGoogleClientID.isUsed(type: "drive", config: ["client_id": "x.apps.googleusercontent.com"]))
        #expect(!SharedGoogleClientID.isUsed(type: "drive", config: ["service_account_file": "/k.json"]))
        #expect(!SharedGoogleClientID.isUsed(type: "drive", config: ["service_account_credentials": "{}"]))
        #expect(!SharedGoogleClientID.isUsed(type: "onedrive", config: [:]))
        #expect(!SharedGoogleClientID.isUsed(type: "s3", config: [:]))
    }

    @Test func validatesAndTrimsThePair() throws {
        let pair = try SharedGoogleClientID.validate(
            id: "  123-abc.apps.googleusercontent.com\n", secret: " shh "
        ).get()
        #expect(pair.id == "123-abc.apps.googleusercontent.com")
        #expect(pair.secret == "shh")
    }

    @Test func rejectsWhatIsNotAGoogleClientID() {
        func problem(_ id: String, _ secret: String) -> SharedGoogleClientID.InputProblem? {
            if case .failure(let issue) = SharedGoogleClientID.validate(id: id, secret: secret) { return issue }
            return nil
        }
        #expect(problem("", "s") == .missingID)
        #expect(problem("   ", "s") == .missingID)
        #expect(problem("my-client", "s") == .notAGoogleID)
        #expect(problem(".apps.googleusercontent.com", "s") == .notAGoogleID)
        #expect(problem("a b.apps.googleusercontent.com", "s") == .notAGoogleID)
        #expect(problem("x.apps.googleusercontent.com", " ") == .missingSecret)
    }

    @Test func savingWritesOnlyThePair() async throws {
        let client = RecordingSaver()
        try await OwnClientIDSheet.save("x.apps.googleusercontent.com", "shh", on: "Personal", with: client)
        #expect(client.calls.count == 1)
        #expect(client.calls[0].name == "Personal")
        #expect(client.calls[0].parameters == ["client_id": "x.apps.googleusercontent.com", "client_secret": "shh"])
    }

    @Test func slowNoticeNamesTheCauseOnlyForTheSharedSignIn() {
        #expect(BrowserView.slowText(usesSharedGoogleID: false) == "Still loading…")
        #expect(BrowserView.slowText(usesSharedGoogleID: true).contains("Google is limiting"))
    }

    @Test func listingsWaitLongerThanTheClientDefault() {
        #expect(BrowserViewModel.listTimeout == 120)
        #expect(BrowserViewModel.slowAfter == .seconds(8))
    }

    @Test func daemonLogAppendsAndDropsTheOlderHalfWhenFull() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-daemon-log-\(UUID().uuidString)/rclone.log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DaemonLog(url: url, limit: 100)

        log.append(Data("first line\n".utf8))
        log.append(Data("second line\n".utf8))
        log.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == "first line\nsecond line\n")

        for index in 0..<20 { log.append(Data("line number \(index)\n".utf8)) }
        log.flush()
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.utf8.count <= 100)
        #expect(text.hasSuffix("line number 19\n"))
        #expect(!text.contains("first line"))
        // It starts on a whole line, not mid-way through one.
        #expect(text.hasPrefix("line number "))
    }

    @Test func daemonLogCollectsWhatAProcessWritesToStderr() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-daemon-log-\(UUID().uuidString)/rclone.log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DaemonLog(url: url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo 'NOTICE: hello from stderr' 1>&2"]
        process.standardError = log.makePipe()
        try process.run()
        process.waitUntilExit()

        var text = ""
        for _ in 0..<50 where !text.contains("hello") {
            Thread.sleep(forTimeInterval: 0.02)
            log.flush()
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        #expect(text == "NOTICE: hello from stderr\n")
    }

    @Test func rendersTheSetupSheet() throws {
        let view = OwnClientIDSheet(cloudName: "Google Drive", client: RecordingSaver(), onSaved: {})
            .background(DesignSystem.Color.semantic.surface)
        try SnapshotHelpers.assertHostedSnapshot(
            view, size: CGSize(width: 520, height: 520), named: "OwnClientID-sheet"
        )
    }
}

private final class RecordingSaver: ClientIDSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(name: String, parameters: [String: String])] = []

    var calls: [(name: String, parameters: [String: String])] { lock.withLock { _calls } }

    func setRemoteParameters(name: String, parameters: [String: String]) async throws {
        lock.withLock { _calls.append((name, parameters)) }
    }
}
