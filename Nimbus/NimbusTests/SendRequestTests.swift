import AppKit
import Foundation
import RcloneKit
import Testing

@testable import Nimbus

@Suite("Send to Nimbus")
@MainActor
struct SendRequestTests {
    private func item(_ name: String, isDirectory: Bool = false, size: Int64? = 10) -> SendRequest.Item {
        SendRequest.Item(url: URL(fileURLWithPath: "/tmp/src/\(name)"), isDirectory: isDirectory,
                         size: isDirectory ? nil : size)
    }

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-send-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: BrowserDrop

    @Test func splitsADropIntoNimbusRefsAndLocalFiles() {
        let ref = NimbusFileRef(remoteName: "b2", path: "bucket/a.txt", size: 1, isDir: false)
        let file = URL(fileURLWithPath: "/tmp/src/b.txt")
        let (refs, urls) = BrowserDrop.split([
            .file(file), .bundle(NimbusFileBundle(refs: [ref])), .file(URL(string: "https://example.com/c.txt")!),
        ])
        #expect(refs == [ref])
        #expect(urls == [file])
    }

    private func loadDrop(_ provider: NSItemProvider) async throws -> BrowserDrop {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: BrowserDrop.self) { continuation.resume(with: $0) }
        }
    }

    @Test func aFinderFileArrivesAsAFileEvenWhenItIsJSON() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        try Data("{}".utf8).write(to: file)
        let provider = try #require(NSItemProvider(contentsOf: file))
        provider.registerObject(file as NSURL, visibility: .all)

        guard case .file(let url) = try await loadDrop(provider) else {
            Issue.record("expected a file drop")
            return
        }
        #expect(url.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func aDragFromInsideNimbusStillArrivesAsABundle() async throws {
        let bundle = NimbusFileBundle(refs: [NimbusFileRef(remoteName: "b2", path: "bucket/a.txt", size: 1, isDir: false)])
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "public.json", visibility: .all) { done in
            done(try? JSONEncoder().encode(bundle), nil)
            return nil
        }

        guard case .bundle(let loaded) = try await loadDrop(provider) else {
            Issue.record("expected a bundle drop")
            return
        }
        #expect(loaded == bundle)
    }

    // MARK: SendRequest

    @Test func keepsExistingFilesOnceAndDropsTheRest() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: file)
        let folder = directory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let request = try #require(SendRequest(urls: [
            file, file, folder, directory.appendingPathComponent("missing.txt"),
            URL(string: "https://example.com/a.txt")!,
        ]))
        #expect(request.items.map(\.name) == ["a.txt", "Folder"])
        #expect(request.items[0].size == 5)
        #expect(request.items[1].isDirectory)
        #expect(request.items[1].size == nil)
    }

    @Test func nothingToSendIsNil() {
        #expect(SendRequest(urls: []) == nil)
        #expect(SendRequest(urls: [URL(fileURLWithPath: "/definitely/not/here.txt")]) == nil)
    }

    @Test func summaryLeavesOutAnUnknownSize() {
        #expect(SendRequest(items: [item("a.txt", size: 1_000_000), item("b.txt", size: 1_000_000)]).summary
            == "2 items · 2 MB")
        #expect(SendRequest(items: [item("a.txt")]).summary.hasPrefix("1 item · "))
        #expect(SendRequest(items: [item("a.txt"), item("Docs", isDirectory: true)]).summary == "2 items")
    }

    @Test func nameListStopsAtThree() {
        let request = SendRequest(items: ["a", "b", "c", "d", "e"].map { item($0) })
        #expect(request.nameList == "a, b, c and 2 more")
        #expect(SendRequest(items: [item("a"), item("b")]).nameList == "a, b")
    }

    // MARK: SendPlan

    @Test func clashesIgnoreCase() {
        let items = [item("Report.pdf"), item("new.txt")]
        #expect(SendPlan.clashes(items, existing: ["report.PDF", "other"]) == ["Report.pdf"])
        #expect(SendPlan.clashes(items, existing: []).isEmpty)
    }

    @Test func keepBothNumbersFromTwo() {
        #expect(SendPlan.keepBothName("report.pdf", taken: []) == "report.pdf")
        #expect(SendPlan.keepBothName("report.pdf", taken: ["report.pdf"]) == "report 2.pdf")
        #expect(SendPlan.keepBothName("report.pdf", taken: ["report.pdf", "Report 2.pdf"]) == "report 3.pdf")
        #expect(SendPlan.keepBothName("Photos", taken: ["Photos"]) == "Photos 2")
        #expect(SendPlan.keepBothName(".env", taken: [".env"]) == ".env 2")
        #expect(SendPlan.keepBothName("archive.tar.gz", taken: ["archive.tar.gz"]) == "archive.tar 2.gz")
    }

    @Test func replaceKeepsNamesAndKeepBothRenames() {
        let items = [item("a.txt"), item("b.txt")]
        #expect(SendPlan.steps(for: items, existing: ["a.txt"], policy: .replace).map(\.destinationName)
            == ["a.txt", "b.txt"])
        #expect(SendPlan.steps(for: items, existing: ["a.txt"], policy: .keepBoth).map(\.destinationName)
            == ["a 2.txt", "b.txt"])
    }

    @Test func twoSentItemsWithOneNameNeverCollide() {
        let first = SendRequest.Item(url: URL(fileURLWithPath: "/tmp/one/a.txt"), isDirectory: false, size: 1)
        let second = SendRequest.Item(url: URL(fileURLWithPath: "/tmp/two/a.txt"), isDirectory: false, size: 1)
        #expect(SendPlan.steps(for: [first, second], existing: [], policy: .replace).map(\.destinationName)
            == ["a.txt", "a 2.txt"])
    }

    @Test func destinationPathHasNoStraySlashes() {
        #expect(SendPlan.destinationPath(folder: "", name: "a.txt") == "a.txt")
        #expect(SendPlan.destinationPath(folder: "/Inbox/", name: "a.txt") == "Inbox/a.txt")
        #expect(SendPlan.destinationPath(folder: "Inbox/2026", name: "a.txt") == "Inbox/2026/a.txt")
    }

    // MARK: SendViewModel

    private func model(
        _ items: [SendRequest.Item], client: FakeSendClient, remotes: [String] = ["drive", "b2"],
        lastRemote: String? = nil, lastPath: String? = nil
    ) -> SendViewModel {
        SendViewModel(request: SendRequest(items: items), remoteNames: remotes, lastRemote: lastRemote,
                      lastPath: lastPath, client: client)
    }

    @Test func startsAtTheLastDestinationWhenThatCloudStillExists() {
        let remembered = model([item("a")], client: FakeSendClient(), lastRemote: "b2", lastPath: "Inbox")
        #expect(remembered.remote == "b2")
        #expect(remembered.path == "Inbox")

        let gone = model([item("a")], client: FakeSendClient(), lastRemote: "deleted", lastPath: "Inbox")
        #expect(gone.remote == "drive")
        #expect(gone.path == "")

        let none = model([item("a")], client: FakeSendClient(), remotes: [])
        #expect(!none.canSend)
    }

    @Test func sendsFilesAndFoldersAndRecordsTransfers() async {
        let client = FakeSendClient()
        let store = TransferStore()
        let model = model([item("a.txt"), item("Docs", isDirectory: true)], client: client)
        model.path = "Inbox"

        #expect(await model.send(policy: nil, store: store))
        #expect(client.calls == [
            "file /tmp/src a.txt -> drive:Inbox/a.txt",
            "folder /tmp/src/Docs -> drive:Inbox/Docs",
        ])
        #expect(store.transfers.map(\.dstFs) == ["drive:Inbox/a.txt", "drive:Inbox/Docs"])
        #expect(store.transfers.allSatisfy { $0.origin == .sendToNimbus })
    }

    @Test func aClashStopsAndAsksBeforeCopyingAnything() async {
        let client = FakeSendClient(existing: ["a.txt"])
        let store = TransferStore()
        let model = model([item("a.txt"), item("b.txt")], client: client)

        #expect(await model.send(policy: nil, store: store) == false)
        #expect(model.clashes == ["a.txt"])
        #expect(client.calls.isEmpty)
        #expect(store.transfers.isEmpty)

        #expect(await model.send(policy: .keepBoth, store: store))
        #expect(client.calls == ["file /tmp/src a.txt -> drive:a 2.txt", "file /tmp/src b.txt -> drive:b.txt"])
    }

    @Test func changingTheFolderForgetsTheOldClashes() async {
        let client = FakeSendClient(existing: ["a.txt"])
        let model = model([item("a.txt")], client: client)
        _ = await model.send(policy: nil, store: TransferStore())
        #expect(!model.clashes.isEmpty)
        model.path = "Elsewhere"
        #expect(model.clashes.isEmpty)
    }

    @Test func aRefusalShowsAnErrorAndSendsNothing() async {
        let client = FakeSendClient(failListing: true)
        let store = TransferStore()
        let model = model([item("a.txt")], client: client)

        #expect(await model.send(policy: nil, store: store) == false)
        #expect(model.error != nil)
        #expect(store.transfers.isEmpty)
    }

    // MARK: Services

    @Test func servicePasteboardBecomesARequest() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("nimbus-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        #expect(NimbusServicesProvider.request(from: pasteboard)?.items.map(\.name) == ["a.txt"])

        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        #expect(NimbusServicesProvider.request(from: pasteboard) == nil)
    }

    @Test func aRequestThatArrivesBeforeTheHandlerWaitsForIt() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("nimbus-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])

        let provider = NimbusServicesProvider()
        var error: NSString = ""
        withUnsafeMutablePointer(to: &error) { pointer in
            provider.sendToNimbus(pasteboard, userData: nil, error: AutoreleasingUnsafeMutablePointer(pointer))
        }
        var received: [SendRequest] = []
        provider.onSend = { received.append($0) }
        #expect(received.count == 1)
        #expect(received.first?.items.first?.name == "a.txt")
    }

    // MARK: Share

    @Test func shareDownloadsFromTheFullPathAndCleansUp() async throws {
        let client = RecordingDownloadClient()
        let host = ShareHost()
        let file = FileItem(path: "a.txt", name: "a.txt", size: 1, mimeType: "", modTime: nil, isDir: false,
                            fileID: nil, qualifiedRemotePath: "drive:Docs/2026/a.txt")

        let urls = try await host.materialize([file], remote: "drive", client: client)
        #expect(client.paths == ["Docs/2026/a.txt"])
        #expect(FileManager.default.fileExists(atPath: urls[0].path))

        // The next share replaces the last one's downloads.
        _ = try await host.materialize([file], remote: "drive", client: client)
        #expect(!FileManager.default.fileExists(atPath: urls[0].path))
        host.dispose()
    }

    @Test func aFailedShareLeavesNothingBehind() async {
        let client = RecordingDownloadClient(failAfter: 1)
        let host = ShareHost()
        let files = ["a.txt", "b.txt"].map {
            FileItem(path: $0, name: $0, size: 1, mimeType: "", modTime: nil, isDir: false, fileID: nil,
                     qualifiedRemotePath: "drive:\($0)")
        }
        await #expect(throws: (any Error).self) {
            _ = try await host.materialize(files, remote: "drive", client: client)
        }
        #expect(client.urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}

private final class FakeSendClient: SendClient, @unchecked Sendable {
    private let existing: Set<String>
    private let failListing: Bool
    private let lock = NSLock()
    private var _calls: [String] = []

    init(existing: Set<String> = [], failListing: Bool = false) {
        self.existing = existing
        self.failListing = failListing
    }

    var calls: [String] { lock.withLock { _calls } }

    func names(remote _: String, path _: String) async throws -> Set<String> {
        if failListing { throw CocoaError(.fileReadUnknown) }
        return existing
    }

    func copyFile(localDirectory: String, name: String, remote: String, destinationPath: String) async throws -> Int {
        lock.withLock {
            _calls.append("file \(localDirectory) \(name) -> \(remote):\(destinationPath)")
            return _calls.count
        }
    }

    func copyFolder(localPath: String, remote: String, destinationPath: String) async throws -> Int {
        lock.withLock {
            _calls.append("folder \(localPath) -> \(remote):\(destinationPath)")
            return _calls.count
        }
    }
}

private final class RecordingDownloadClient: RcloneClientProtocol, @unchecked Sendable {
    private let failAfter: Int?
    private let lock = NSLock()
    private var _paths: [String] = []
    private var _urls: [URL] = []

    init(failAfter: Int? = nil) {
        self.failAfter = failAfter
    }

    var paths: [String] { lock.withLock { _paths } }
    var urls: [URL] { lock.withLock { _urls } }

    func downloadToTemp(remote _: String, path: String) async throws -> URL {
        if let failAfter, lock.withLock({ _paths.count }) >= failAfter { throw CocoaError(.fileReadUnknown) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-share-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent((path as NSString).lastPathComponent)
        try Data("x".utf8).write(to: url)
        lock.withLock {
            _paths.append(path)
            _urls.append(url)
        }
        return url
    }
}
