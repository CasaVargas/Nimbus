import Testing
import SwiftUI
import AppKit

enum SnapshotHelpers {
    /// Hamming-distance threshold for perceptual hash comparison. ~3% of 256 bits.
    static let hashTolerance = 8

    /// Renders a SwiftUI view to a deterministic PNG `Data` blob via ImageRenderer.
    @MainActor
    static func renderPNG<V: View>(_ view: V, size: CGSize) -> Data {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return Data() }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = size
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Computes a 256-bit perceptual hash from PNG data.
    /// Downsamples the image to 16×16 grayscale, then sets each bit based on
    /// whether the pixel's luminance is above the image mean.
    static func perceptualHash(of pngData: Data) -> [UInt8] {
        guard let image = NSImage(data: pngData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Array(repeating: 0, count: 32)
        }

        let targetSize = 16
        let bytesPerPixel = 1
        let bytesPerRow = targetSize * bytesPerPixel
        let totalBytes = targetSize * targetSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return Array(repeating: 0, count: 32)
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        // Compute mean luminance
        let total = pixels.reduce(0) { $0 + Int($1) }
        let mean = UInt8(total / pixels.count)

        // Pack 256 bits into 32 bytes
        var hash = [UInt8](repeating: 0, count: 32)
        for (index, pixel) in pixels.enumerated() {
            if pixel > mean {
                let byteIndex = index / 8
                let bitIndex = 7 - (index % 8)
                hash[byteIndex] |= (1 << bitIndex)
            }
        }
        return hash
    }

    /// Hamming distance: number of differing bits between two equal-length hashes.
    static func hammingDistance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        precondition(a.count == b.count, "hashes must be equal length")
        var distance = 0
        for i in 0..<a.count {
            var xor = a[i] ^ b[i]
            while xor != 0 {
                distance += Int(xor & 1)
                xor >>= 1
            }
        }
        return distance
    }

    /// Compares rendered output against a stored fixture via perceptual hash.
    /// On first run (or with NIMBUS_SNAPSHOT_RECORD=1), writes the fixture PNG.
    /// On subsequent runs, computes a perceptual hash for both and fails if
    /// the Hamming distance exceeds `hashTolerance` (default 8 bits / 256 = ~3%).
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
        let renderedHash = perceptualHash(of: rendered)
        let expectedHash = perceptualHash(of: expected)
        let distance = hammingDistance(renderedHash, expectedHash)

        #expect(
            distance <= hashTolerance,
            """
            Snapshot perceptual mismatch for \(name).
            Hamming distance: \(distance) bits (tolerance: \(hashTolerance)).
            Fixture: \(fixtureURL.path)
            Save the rendered PNG with NIMBUS_SNAPSHOT_RECORD=1 to update.
            """
        )
    }
}
