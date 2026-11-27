import Foundation
import RcloneKit
import Testing
@testable import Nimbus

/// Dedicated mock transport for `BrowserViewModelTests` so concurrent suites
/// never share RC request state.
private final class BrowserMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct RecordedRequest: Sendable {
        let endpoint: String
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responder: (@Sendable (String, Data) -> (Int, String))?
    nonisolated(unsafe) private static var recorded: [RecordedRequest] = []

    static func configure(_ handler: @escaping @Sendable (String, Data) -> (Int, String)) {
        lock.withLock {
            responder = handler
            recorded = []
        }
    }

    static var requests: [RecordedRequest] {
        lock.withLock { recorded }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://127.0.0.1")!
        let endpoint = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let (status, payload): (Int, String) = Self.lock.withLock {
            Self.recorded.append(RecordedRequest(endpoint: endpoint, body: body))
            return Self.responder?(endpoint, body) ?? (200, "{}")
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("BrowserViewModel fixed top level", .serialized)
@MainActor
struct BrowserViewModelTests {
    private func makeViewModel(
        remote: String = "clouds",
        responder: @escaping @Sendable (String, Data) -> (Int, String)
    ) -> BrowserViewModel {
        BrowserMockURLProtocol.configure(responder)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserMockURLProtocol.self]
        let client = RcloneClient(port: 5572, session: URLSession(configuration: config))
        let vm = BrowserViewModel(client: client)
        vm.remote = remote
        return vm
    }

    private nonisolated static func listJSON(_ items: [(path: String, name: String, isDir: Bool)]) -> String {
        let entries = items.map { item in
            #"{"Path":"\#(item.path)","Name":"\#(item.name)","Size":0,"MimeType":"","ModTime":"2026-01-01T00:00:00Z","IsDir":\#(item.isDir ? "true" : "false")}"#
        }
        return #"{"list":[\#(entries.joined(separator: ","))]}"#
    }

    @Test func protectsTopLevelOnlyAtRoot() async {
        let vm = makeViewModel { endpoint, _ in
            switch endpoint {
            case "config/get": (200, #"{"type":"combine"}"#)
            case "operations/list": (200, Self.listJSON([("gdrive", "gdrive", true)]))
            default: (200, "{}")
            }
        }
        await vm.loadFiles()
        #expect(vm.hasFixedTopLevel)
        #expect(vm.protectsTopLevel)

        await vm.navigateTo(path: "gdrive")
        #expect(vm.hasFixedTopLevel)
        #expect(!vm.protectsTopLevel)
    }

    @Test func loadFilesRechecksConfigChangesAndKeepsLastValueOnError() async {
        let lock = NSLock()
        nonisolated(unsafe) var configResponse: (Int, String) = (500, #"{"error":"starting"}"#)

        let vm = makeViewModel { endpoint, _ in
            switch endpoint {
            case "config/get": lock.withLock { configResponse }
            case "operations/list": (200, #"{"list":[]}"#)
            default: (200, "{}")
            }
        }

        // First load hits a transient config/get failure: does not lock in false.
        await vm.loadFiles()
        #expect(!vm.hasFixedTopLevel)

        // Retry after daemon recovers: picks up fixed top level.
        lock.withLock { configResponse = (200, #"{"type":"combine"}"#) }
        await vm.loadFiles()
        #expect(vm.hasFixedTopLevel)
        #expect(vm.protectsTopLevel)

        // Subsequent transient failure preserves the last known value.
        lock.withLock { configResponse = (500, #"{"error":"busy"}"#) }
        await vm.loadFiles()
        #expect(vm.hasFixedTopLevel)

        // Config edited to a regular remote: next refresh clears the flag.
        lock.withLock { configResponse = (200, #"{"type":"drive"}"#) }
        await vm.loadFiles()
        #expect(!vm.hasFixedTopLevel)
        #expect(!vm.protectsTopLevel)
    }

    @Test func deleteItemsRefusesTopLevelAndAllowsNested() async throws {
        let vm = makeViewModel { endpoint, _ in
            switch endpoint {
            case "config/get": (200, #"{"type":"combine"}"#)
            case "operations/list":
                (200, Self.listJSON([("gdrive", "gdrive", true), ("gdrive/note.txt", "note.txt", false)]))
            default: (200, "{}")
            }
        }
        await vm.loadFiles()

        await #expect(throws: BrowserActionError.fixedTopLevelDelete) {
            try await vm.deleteItems(paths: ["gdrive"])
        }
        #expect(!BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/purge" || $0.endpoint == "operations/deletefile" })

        try await vm.deleteItems(paths: ["gdrive/note.txt"])
        #expect(BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/deletefile" })
    }

    @Test func renameItemRefusesTopLevelAndAllowsNested() async throws {
        let vm = makeViewModel { endpoint, _ in
            switch endpoint {
            case "config/get": (200, #"{"type":"combine"}"#)
            case "operations/list": (200, #"{"list":[]}"#)
            default: (200, "{}")
            }
        }

        await #expect(throws: BrowserActionError.fixedTopLevelRename) {
            try await vm.renameItem(oldPath: "gdrive", newName: "renamed")
        }
        #expect(!BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/movefile" })

        try await vm.renameItem(oldPath: "gdrive/old.txt", newName: "new.txt")
        #expect(BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/movefile" })
    }

    @Test func createFolderRefusesAtRootAndAllowsInSubfolder() async throws {
        let vm = makeViewModel { endpoint, _ in
            switch endpoint {
            case "config/get": (200, #"{"type":"combine"}"#)
            case "operations/fsinfo": (200, #"{"Features":{"CanHaveEmptyDirectories":true}}"#)
            case "operations/list": (200, #"{"list":[]}"#)
            default: (200, "{}")
            }
        }

        await #expect(throws: BrowserActionError.fixedTopLevelCreate) {
            try await vm.createFolder(name: "newroot")
        }
        #expect(!BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/mkdir" })

        vm.path = "gdrive"
        try await vm.createFolder(name: "Sub")
        #expect(BrowserMockURLProtocol.requests.contains { $0.endpoint == "operations/mkdir" })
    }
}
