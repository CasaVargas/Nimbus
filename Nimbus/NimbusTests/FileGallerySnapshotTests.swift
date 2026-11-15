import CoreGraphics
import Foundation
import RcloneKit
import SwiftUI
import Testing

@testable import Nimbus

@Suite("FileGallery", .serialized)
@MainActor
struct FileGallerySnapshotTests {
    @Test func usesTheSpecMetrics() {
        #expect(FileGallery.Layout.cellSize == 72)
        #expect(FileGallery.Layout.cellMaxPixel == 144)
        #expect(FileGallery.Layout.previewMaxPixel == 1600)
    }

    @Test func captionLeavesOutWhatIsUnknown() {
        #expect(FileGallery.detail(for: Self.item("Scans", isDir: true, modTime: nil)) == "Folder")
        #expect(FileGallery.detail(for: Self.item("mystery.bin", size: -1, modTime: nil)) == "")
        #expect(FileGallery.detail(for: Self.item("a.png", size: 2_000_000, modTime: nil)) == "2 MB")
        #expect(FileGallery.detail(for: Self.item("a.png", size: 2_000_000)).hasPrefix("2 MB · "))
    }

    /// A photo (selected), a PDF, a folder and a file too large for a
    /// picture. Pictures come from a stub that answers at once, so the
    /// render doesn't depend on timing.
    @Test func rendersPreviewOverFilmstrip() throws {
        let files = [
            Self.item("beach.png"),
            Self.item("contract.pdf"),
            Self.item("Scans", isDir: true),
            Self.item("raw-footage.png", size: 30 * 1024 * 1024),
            Self.item("notes.md"),
        ]
        let selection = Selection<String>()
        selection.select(files[0].id, in: files.map(\.id))

        let view = FileGallery(
            files: files, remote: "drive", selection: selection,
            thumbnails: StubThumbnails(),
            onOpen: { _ in }, onContextAction: { _, _ in }, onQuickLook: { _ in }
        )
        .background(DesignSystem.Color.semantic.surface)

        try SnapshotHelpers.assertHostedSnapshot(
            view, size: CGSize(width: 640, height: 420), named: "FileGallery-photo-selected"
        )
    }

    @Test func worksOnIconsAloneWithoutAProvider() throws {
        let files = [Self.item("Scans", isDir: true), Self.item("notes.md")]
        let selection = Selection<String>()

        let view = FileGallery(
            files: files, remote: "drive", selection: selection, thumbnails: nil,
            onOpen: { _ in }, onContextAction: { _, _ in }, onQuickLook: { _ in }
        )
        .background(DesignSystem.Color.semantic.surface)

        try SnapshotHelpers.assertHostedSnapshot(
            view, size: CGSize(width: 640, height: 420), named: "FileGallery-icons-only"
        )
        // Entering the mode with nothing selected selects the first item.
        #expect(selection.ids == [files[0].id])
    }

    private static func item(
        _ name: String, isDir: Bool = false, size: Int64 = 3_250_000,
        modTime: Date? = Date(timeIntervalSince1970: 1_794_000_000)
    ) -> FileItem {
        FileItem(
            path: name, name: name, size: isDir ? -1 : size, mimeType: "", modTime: modTime,
            isDir: isDir, fileID: nil, qualifiedRemotePath: "drive:\(name)"
        )
    }
}

/// Answers every allowed request at once with a flat-colored picture:
/// landscape orange for photos, portrait white for PDFs.
private struct StubThumbnails: GalleryThumbnailProviding {
    func cachedImage(for request: ThumbnailRequest) -> CGImage? {
        switch request.kind {
        case .image: Self.fill(width: 300, height: 200, red: 0.95, green: 0.55, blue: 0.2)
        case .pdf: Self.fill(width: 170, height: 220, red: 1, green: 1, blue: 1)
        case nil: nil
        }
    }

    func image(for request: ThumbnailRequest) async -> CGImage? {
        cachedImage(for: request)
    }

    private static func fill(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
