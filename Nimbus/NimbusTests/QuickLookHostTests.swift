import Foundation
import RcloneKit
import Testing

@testable import Nimbus

@Suite("QuickLookHost MaterializationProvider selection and cleanup")
@MainActor
struct QuickLookHostTests {
    /// Regression guard for 18aea09: even when a remote is FP-mounted, Quick
    /// Look must use a full temp download, NOT the File-Provider placeholder.
    /// The placeholder path left types that can't render without full bytes
    /// (e.g. an mp3 from a registered remote) opening blank. Do not "restore"
    /// FileProviderMaterializationProvider selection here without re-checking
    /// that bug.
    @Test func fileProviderMountedRemoteStillUsesTempDownloadProvider() {
        let bridge = StubFileProviderBridge(mountedRemotes: ["gdrive"])
        let provider = QuickLookHost.provider(
            forRemote: "gdrive",
            bridge: bridge,
            client: StubRcloneClient()
        )
        #expect(provider is TempDownloadMaterializationProvider)
    }

    @Test func unmountedRemoteUsesTempDownloadProvider() {
        let bridge = StubFileProviderBridge(mountedRemotes: [])
        let provider = QuickLookHost.provider(
            forRemote: "s3",
            bridge: bridge,
            client: StubRcloneClient()
        )
        #expect(provider is TempDownloadMaterializationProvider)
    }

    @Test func tempDownloadProviderCreatesAndCleansUpTempFile() async throws {
        let client = StubRcloneClient()
        let provider = TempDownloadMaterializationProvider(client: client)
        let item = makeStubFileItem(name: "foo.txt", path: "/foo.txt")

        let url = try await provider.resolveURL(for: item, remote: "test")
        #expect(FileManager.default.fileExists(atPath: url.path))

        provider.dispose()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func emptyItemsDoesNotOpenPanel() async {
        let host = QuickLookHost()
        let provider = TempDownloadMaterializationProvider(client: StubRcloneClient())
        await host.show(items: [], provider: provider, remote: "test")
        // No assertion needed — if it crashes or hangs, test fails. Behaviorally,
        // panel should remain un-shown. We can't easily query QLPreviewPanel state
        // in tests, so this is primarily a smoke test for the empty guard.
    }

    @Test func showReentryDisposesPreviousProvider() async throws {
        let host = QuickLookHost()
        let client = StubRcloneClient()
        let first = TempDownloadMaterializationProvider(client: client)
        let second = TempDownloadMaterializationProvider(client: client)

        // First resolve creates a temp URL.
        let item = makeStubFileItem(name: "first.txt", path: "first.txt")
        let firstURL = try await first.resolveURL(for: item, remote: "test")
        #expect(FileManager.default.fileExists(atPath: firstURL.path))

        // Hand `first` to the host so the host owns dispose responsibility.
        await host.show(items: [item], provider: first, remote: "test")

        // Re-entry: host should dispose `first` before taking ownership of `second`.
        await host.show(items: [item], provider: second, remote: "test")

        // First's temp dir should have been cleaned up by the re-entry teardown.
        #expect(FileManager.default.fileExists(atPath: firstURL.path) == false)
    }

    @Test func qualifiedRemotePathReconstructsFullPath() async throws {
        // Verify the FileProviderMaterializationProvider strips the "remote:" prefix
        // from qualifiedRemotePath and passes the full path-from-root to the bridge.
        let bridge = RecordingFileProviderBridge(mountedRemotes: ["gdrive"])
        let provider = FileProviderMaterializationProvider(bridge: bridge)
        let item = FileItem(
            path: "deep.txt", // leaf name only
            name: "deep.txt",
            size: 12,
            mimeType: "text/plain",
            modTime: nil,
            isDir: false,
            fileID: nil,
            qualifiedRemotePath: "gdrive:Photos/2026/deep.txt" // full path from remote root
        )
        _ = try? await provider.resolveURL(for: item, remote: "gdrive")
        #expect(bridge.lastRequestedPath == "Photos/2026/deep.txt")
    }
}

// MARK: - Stubs

@MainActor
private final class StubFileProviderBridge: FileProviderBridgeProtocol {
    let mountedRemotes: Set<String>

    init(mountedRemotes: Set<String>) {
        self.mountedRemotes = mountedRemotes
    }

    func isRegistered(remote: String) -> Bool {
        mountedRemotes.contains(remote)
    }

    func urlForItem(remote: String, path: String) async -> URL? {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-fp-\(remote)\(path)")
    }

    func isItemMaterialized(remote _: String, path _: String) async -> Bool { false }
    func wasRecentlyEvicted(remote _: String, path _: String) async -> Bool { false }
}

@MainActor
private final class RecordingFileProviderBridge: FileProviderBridgeProtocol {
    let mountedRemotes: Set<String>
    var lastRequestedPath: String?

    init(mountedRemotes: Set<String>) {
        self.mountedRemotes = mountedRemotes
    }

    func isRegistered(remote: String) -> Bool {
        mountedRemotes.contains(remote)
    }

    func urlForItem(remote: String, path: String) async -> URL? {
        lastRequestedPath = path
        return FileManager.default.temporaryDirectory.appendingPathComponent("fake-\(remote)-\(path)")
    }

    func isItemMaterialized(remote _: String, path _: String) async -> Bool { false }
    func wasRecentlyEvicted(remote _: String, path _: String) async -> Bool { false }
}

private final class StubRcloneClient: RcloneClientProtocol, @unchecked Sendable {
    func downloadToTemp(remote _: String, path: String) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nimbus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent((path as NSString).lastPathComponent)
        try Data("stub-content".utf8).write(to: url)
        return url
    }
}

private func makeStubFileItem(name: String, path: String) -> FileItem {
    FileItem(
        path: path,
        name: name,
        size: 12,
        mimeType: "text/plain",
        modTime: nil,
        isDir: false,
        fileID: nil,
        qualifiedRemotePath: "test:\(path)"
    )
}
