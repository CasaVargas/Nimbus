import Testing
import SwiftUI
import AppKit

enum SnapshotHelpers {
    /// Renders a SwiftUI view to a deterministic PNG `Data` blob.
    @MainActor
    static func renderPNG<V: View>(_ view: V, size: CGSize) -> Data {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return Data() }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Compares rendered output against a stored fixture. On first run, writes the fixture.
    /// Override behavior with NIMBUS_SNAPSHOT_RECORD=1 to regenerate all fixtures.
    @MainActor
    static func assertSnapshot<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 240, height: 40),
        named name: String,
        fileID: String = #fileID
    ) throws {
        let rendered = renderPNG(view, size: size)
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)

        let fixtureURL = fixturesDir.appendingPathComponent("\(name).png")
        let record = ProcessInfo.processInfo.environment["NIMBUS_SNAPSHOT_RECORD"] == "1"

        if record || !FileManager.default.fileExists(atPath: fixtureURL.path) {
            try rendered.write(to: fixtureURL)
            Issue.record("Recorded fixture \(fixtureURL.lastPathComponent); rerun without record env to verify.")
            return
        }

        let expected = try Data(contentsOf: fixtureURL)
        #expect(rendered == expected, "Snapshot mismatch for \(name). Compare \(fixtureURL.path).")
    }
}
