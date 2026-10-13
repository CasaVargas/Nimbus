import Testing
import SwiftUI
import AppKit

enum SnapshotHelpers {
    /// Hamming-distance threshold for perceptual hash comparison. ~3% of 256 bits.
    static let hashTolerance = 8

    /// Retained solely for hosted snapshots. Reusing one non-key window avoids
    /// AppKit's back-to-back window setup race while keeping focus out of the
    /// captured controls.
    @MainActor private static var hostedWindow: NSWindow?
    @MainActor private static var chromeWindow: NSWindow?

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

    /// Renders macOS controls that ImageRenderer cannot flatten, such as
    /// toggles inside a ScrollView, through a real AppKit hosting view.
    @MainActor
    static func renderHostedPNG<V: View>(_ view: V, size: CGSize) -> Data {
        let hostingView = NSHostingView(rootView: view)
        let window = hostedWindow ?? makeHostedWindow(size: size)
        window.setContentSize(size)
        window.contentView = hostingView

        // Native SwiftUI controls finish configuring only once their hosting
        // hierarchy is attached to and displayed by an AppKit window. Keep
        // the window non-key so focus rings and active-control tint are not
        // captured, then complete two deterministic display passes.
        window.display()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        window.display()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return Data()
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Renders a full NSWindow frame, including titlebar and toolbar-hosted
    /// tab controls, for views whose native chrome lives outside contentView.
    @MainActor
    static func renderWindowPNG<V: View>(
        _ view: V,
        contentSize: CGSize,
        configureWindow: (NSWindow) -> Void = { _ in }
    ) -> Data {
        let controller = NSHostingController(rootView: view.frame(width: contentSize.width, height: contentSize.height))
        let window = chromeWindow ?? makeChromeWindow(contentSize: contentSize)
        window.setContentSize(contentSize)
        window.contentViewController = controller
        configureWindow(window)

        controller.view.needsLayout = true
        window.contentView?.needsLayout = true
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        controller.view.needsLayout = true
        window.contentView?.needsLayout = true
        window.display()

        guard let frameView = window.contentView?.superview else {
            return Data()
        }

        // cacheDisplay, not dataWithPDF: the hosted SwiftUI content is
        // layer-backed and does not participate in PDF drawing, so the PDF
        // path captures only the window chrome (an empty dark frame).
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            return Data()
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    @MainActor
    private static func makeHostedWindow(size: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.hasShadow = false
        window.orderFront(nil)
        hostedWindow = window
        return window
    }

    @MainActor
    private static func makeChromeWindow(contentSize: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.orderFront(nil)
        chromeWindow = window
        return window
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
        try assertPNG(rendered, named: name, fileID: fileID)
    }

    /// Snapshot assertion for views that contain native AppKit-backed controls.
    @MainActor
    static func assertHostedSnapshot<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 240, height: 40),
        named name: String,
        fileID: String = #fileID
    ) throws {
        let rendered = renderHostedPNG(view, size: size)
        try assertPNG(rendered, named: name, fileID: fileID)
    }

    @MainActor
    static func assertWindowSnapshot<V: View>(
        _ view: V,
        contentSize: CGSize,
        configureWindow: (NSWindow) -> Void = { _ in },
        named name: String,
        fileID: String = #fileID
    ) throws {
        let rendered = renderWindowPNG(
            view,
            contentSize: contentSize,
            configureWindow: configureWindow
        )
        try assertPNG(rendered, named: name, fileID: fileID)
    }

    @MainActor
    private static func assertPNG(
        _ rendered: Data,
        named name: String,
        fileID: String
    ) throws {
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
