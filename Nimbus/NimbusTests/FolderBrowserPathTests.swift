import Testing
import RcloneKit
@testable import Nimbus

@Suite("Folder picker navigation")
@MainActor
struct FolderBrowserPathTests {
    @Test func nestedSMBPathsDoNotRepeatTheShare() {
        var segments: [String] = []
        enter("BACKUP", segments: &segments)
        #expect(segments == ["BACKUP"])
        enter("BACKUP/RAW 2025", segments: &segments)
        #expect(segments == ["BACKUP", "RAW 2025"])
        #expect(segments.joined(separator: "/") == "BACKUP/RAW 2025")
        enter("BACKUP/RAW 2025/November", segments: &segments)
        #expect(segments == ["BACKUP", "RAW 2025", "November"])

        // Going back to the share and entering a sibling must also work.
        segments = Array(segments.prefix(1))
        enter("BACKUP/Exports", segments: &segments)
        #expect(segments.joined(separator: "/") == "BACKUP/Exports")
    }

    @Test func repeatedFolderNamesAndUnicodeRemainIntact() {
        var segments = ["Photos"]
        enter("Photos/Photos/日本語 📷", segments: &segments)
        #expect(segments == ["Photos", "Photos", "日本語 📷"])
    }

    private func enter(_ path: String, segments: inout [String]) {
        let folder = FileItem(
            path: path, name: String(path.split(separator: "/").last!),
            size: -1, mimeType: "inode/directory", modTime: nil,
            isDir: true, fileID: nil, qualifiedRemotePath: path
        )
        FolderBrowserSheet.enterFolder(folder, segments: &segments)
    }
}
