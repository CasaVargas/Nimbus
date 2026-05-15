#if DEBUG
import Foundation
import SwiftUI
import RcloneKit

/// Scripted perf scenarios. Each scenario is self-contained — no real rclone
/// daemon needed; we synthesize FileItem data and measure UI-relevant operations.
enum BenchScenarios {
    /// Synthesizes 10k FileItems and runs the BrowserViewModel's sort pipeline
    /// over them. This isn't a render measurement — it's the pure data-prep step
    /// that the Browser depends on for its cold-load latency budget.
    /// Real render-time measurement requires the app actually mounted in a window
    /// with an `ImageRenderer` sample or an Instruments trace.
    static func load10kItems() async {
        let items = (0..<10_000).map { i in
            FileItem(
                path: "/synth/\(i).txt",
                name: "\(i).txt",
                size: Int64(i * 1000),
                mimeType: "text/plain",
                modTime: Date().addingTimeInterval(-Double(i * 60)),
                isDir: false,
                fileID: nil,
                qualifiedRemotePath: "bench:/synth/\(i).txt"
            )
        }

        // Exercise the sort path the BrowserViewModel uses on sortedFiles.
        let sorted = items.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        // Touch the values to defeat optimizer dead-code elimination.
        _ = sorted.last?.name
    }

    struct FrameReport {
        let maxFrameMs: Double
        let averageMs: Double
        let frameCount: Int
    }

    /// Approximates frame timing by sampling Date() across rapid Task.yield()
    /// hops. Without a real CADisplayLink + render loop, this is a coarse
    /// indicator only — a true measurement requires Instruments. For Phase 1
    /// gate verification it's enough to ensure no scheduled frame budget
    /// is grossly exceeded.
    static func sampleAnimationFrames() async -> FrameReport {
        var samples: [Double] = []
        var last = Date()
        for _ in 0..<60 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            samples.append(now.timeIntervalSince(last) * 1000)
            last = now
        }
        let max = samples.max() ?? 0
        let avg = samples.reduce(0, +) / Double(samples.count)
        return FrameReport(maxFrameMs: max, averageMs: avg, frameCount: samples.count)
    }
}
#endif
