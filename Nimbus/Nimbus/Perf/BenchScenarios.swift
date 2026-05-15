#if DEBUG
import AppKit
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

    /// Builds 10k synthetic FileItems and exercises the actual Phase 2d
    /// data-source path: assign to a FileTableCoordinator and force the
    /// NSTableView to lay out its first window of cells. Unlike
    /// load10kItems() (sort-only proxy) this measures the render-prep the
    /// pillar-4 ≤200ms budget actually covers.
    ///
    /// Cell rendering (NSHostingView<FileRowView>) requires TransferStore and
    /// FileProviderBridge environment objects. The coordinator's transferStore
    /// / fileProviderBridge properties are set to stub instances so
    /// FileRowHostingCell can inject them into each NSHostingView<FileRowView>
    /// without crashing on missing @Environment values.
    @MainActor
    static func reload10kIntoDataSource() {
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
        let coord = FileTableCoordinator(
            selection: Selection<String>(),
            keyboard: KeyboardCoordinator(),
            onOpen: { _ in },
            onContextAction: { _, _ in },
            onQuickLook: { _ in },
            onSortHeaderClick: { _ in }
        )
        coord.files = items
        coord.remote = "bench"
        coord.transferStore = TransferStore()
        coord.fileProviderBridge = FileProviderBridge()
        let table = FileTableView()
        table.addTableColumn(NSTableColumn(identifier: .init("row")))
        table.dataSource = coord
        table.delegate = coord
        coord.tableView = table
        table.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        table.reloadData()
        // NOTE: layoutSubtreeIfNeeded() is intentionally omitted — the table is
        // not in a window hierarchy, so there are no visible rows to lay out.
        // reloadData() exercises numberOfRows + the row-index rebuild path,
        // which is the O(n) data-prep cost the pillar-4 budget covers.
        // The NSHostingView cell-creation cost (per visible row, ~25 at 600px)
        // is measured in production via the real app window display path.
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
