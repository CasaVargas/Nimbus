import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("FileGrid layout")
@MainActor
struct FileGridLayoutTests {
    @Test func usesCompactFinderStyleMetrics() {
        #expect(FileGrid.Layout.cellWidth == 112)
        #expect(FileGrid.Layout.iconSize == 48)
        #expect(FileGrid.Layout.horizontalSpacing == 8)
        guard case let .adaptive(minimum, maximum) = FileGrid.Layout.column.size else {
            Issue.record("FileGrid must use an adaptive column to fill available width")
            return
        }
        #expect(minimum == FileGrid.Layout.cellWidth)
        #expect(maximum == FileGrid.Layout.cellWidth)
    }

    @Test func rendersCompactGrid() throws {
        let files = [
            Self.item("Documents", isDir: true),
            Self.item("Photos", isDir: true),
            Self.item("quarterly-report.pdf"),
            Self.item("vacation-photo.heic"),
            Self.item("meeting-notes.md"),
            Self.item("archive.zip"),
            Self.item("presentation.mov"),
            Self.item("A filename long enough to wrap.xlsx")
        ]
        let view = LazyVGrid(
            columns: [FileGrid.Layout.column],
            alignment: .leading,
            spacing: FileGrid.Layout.verticalSpacing
        ) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                FileGridTile(file: file, isSelected: index == 2)
            }
        }
        .padding(DesignSystem.Spacing.m)
        .background(DesignSystem.Color.semantic.surface)
        .preferredColorScheme(.dark)

        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 504, height: 224),
            named: "FileGrid-compact"
        )
    }

    private static func item(_ name: String, isDir: Bool = false) -> FileItem {
        FileItem(
            path: "/\(name)",
            name: name,
            size: isDir ? 0 : 1_400_000,
            mimeType: isDir ? "public.folder" : "application/octet-stream",
            modTime: Date(),
            isDir: isDir,
            fileID: nil,
            qualifiedRemotePath: "preview:/\(name)"
        )
    }
}
