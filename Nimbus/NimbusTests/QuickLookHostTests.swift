import Foundation
import RcloneKit
import Testing

@testable import Nimbus

@Suite("QuickLookHost MaterializationProvider selection and cleanup")
@MainActor
struct QuickLookHostTests {
    @Test func fileProviderMountedRemoteUsesFileProviderProvider() {
        let bridge = StubFileProviderBridge(mountedRemotes: ["gdrive"])
        let provider = QuickLookHost.provider(
            forRemote: "gdrive",
            bridge: bridge,
            client: StubRcloneClient()
        )
        #expect(provider is FileProviderMaterializationProvider)
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
