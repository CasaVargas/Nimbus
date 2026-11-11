import Foundation
import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("VersionSupport")
struct VersionSupportTests {
    private func item(_ name: String, isDir: Bool = false) -> FileItem {
        FileItem(path: "bkt/\(name)", name: name, size: 1, mimeType: "text/plain", modTime: nil,
                 isDir: isDir, fileID: nil, qualifiedRemotePath: "c:bkt/\(name)")
    }

    @Test(arguments: ["s3", "b2"])
    func s3AndB2ListVersions(backend: String) {
        #expect(VersionSupport.supports(backendType: backend))
    }

    /// Drive and OneDrive keep revisions rclone can't list; an alias's
    /// `,versions` override wouldn't reach the cloud it points at.
    @Test(arguments: ["sftp", "drive", "onedrive", "dropbox", "alias", "crypt", "imagekit", ""])
    func otherBackendsDoNot(backend: String) {
        #expect(!VersionSupport.supports(backendType: backend))
    }

    @Test func inspectorRowOnlyForFilesOnSupportedClouds() {
        #expect(VersionSupport.showsHistory(for: item("a.txt"), backendType: "s3"))
        #expect(!VersionSupport.showsHistory(for: item("folder", isDir: true), backendType: "s3"))
        #expect(!VersionSupport.showsHistory(for: item("a.txt"), backendType: "sftp"))
        #expect(!VersionSupport.showsHistory(for: item("a.txt"), backendType: nil))
    }

    @Test func downloadNameStampsLocalTime() {
        let date = ISO8601DateFormatter().date(from: "2026-11-11T19:09:48Z")!
        let eastern = TimeZone(identifier: "America/New_York")!
        #expect(VersionSupport.downloadName(for: "report.txt", savedAt: date, timeZone: eastern)
                == "report (2026-11-11 14.09).txt")
        #expect(VersionSupport.downloadName(for: "Makefile", savedAt: date, timeZone: eastern)
                == "Makefile (2026-11-11 14.09)")
    }
}

@Suite("FileVersions snapshots", .serialized)
@MainActor
struct FileVersionsSnapshotTests {
    private let file = FileItem(path: "bkt/docs/report.txt", name: "report.txt", size: 14,
                                mimeType: "text/plain", modTime: nil, isDir: false, fileID: nil,
                                qualifiedRemotePath: "Archive:bkt/docs/report.txt")

    @Test func inspectorRow() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            FileVersionsRow(remote: "Archive", file: file).padding(),
            size: CGSize(width: FileInspector.width, height: 90),
            named: "FileVersions-row")
    }

    @Test func sheetListsVersions() throws {
        let base = ISO8601DateFormatter().date(from: "2026-11-11T19:09:48Z")!
        let versions = [
            FileVersion(path: "a", name: "a", savedAt: base, size: 8_400),
            FileVersion(path: "b", name: "b", savedAt: base.addingTimeInterval(-86_400 * 2), size: 7_900),
            FileVersion(path: "c", name: "c", savedAt: base.addingTimeInterval(-86_400 * 30), size: 1_200),
        ]
        try SnapshotHelpers.assertHostedSnapshot(
            FileVersionsSheet(remote: "Archive", file: file, versionsOverride: versions)
                .environment(RcloneDaemon())
                .environment(TransferStore())
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 440, height: 440),
            named: "FileVersions-sheet")
    }

    @Test func sheetWithNoVersions() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            FileVersionsSheet(remote: "Archive", file: file, versionsOverride: [])
                .environment(RcloneDaemon())
                .environment(TransferStore())
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 440, height: 440),
            named: "FileVersions-empty")
    }
}
