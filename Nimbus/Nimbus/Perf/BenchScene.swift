#if DEBUG
import SwiftUI

/// DEBUG-only scene presenting the Phase 1 perf harness.
/// Reachable via the Debug → Open Bench menu (⌥⌘B).
struct BenchScene: Scene {
    var body: some Scene {
        Window("Nimbus Bench", id: "bench") {
            BenchView()
        }
        .windowResizability(.contentSize)
    }
}

struct BenchView: View {
    @State private var results: [BenchResult] = []
    @State private var running: Bool = false
    @State private var statusMessage: String = "Idle"

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            Text("Performance Harness")
                .font(DesignSystem.Typography.titleEmphasized)

            Text(statusMessage)
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)

            HStack(spacing: DesignSystem.Spacing.s) {
                Button("Run All") { Task { await runAll() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
                Button("10k-item load") { Task { await runDirLoad() } }
                    .disabled(running)
                Button("Animation frames") { Task { await runFrames() } }
                    .disabled(running)
                Spacer()
                Button("Clear") { results.removeAll() }
                    .disabled(running || results.isEmpty)
                Button("Save results JSON") { BenchResult.write(results) }
                    .disabled(running || results.isEmpty)
            }

            Table(results) {
                TableColumn("Scenario") { Text($0.scenario).font(DesignSystem.Typography.body) }
                TableColumn("Result") { r in
                    Text(String(format: "%.1f ms", r.durationMs))
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                }
                TableColumn("Target") { r in
                    Text(r.targetDescription)
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
                TableColumn("Pass") { r in
                    Text(r.passes ? "✅" : "❌")
                        .font(DesignSystem.Typography.body)
                }
            }
            .frame(minHeight: 240)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(minWidth: 720, minHeight: 420)
    }

    private func runAll() async {
        await runDirLoad()
        await runFrames()
        statusMessage = "Done. \(results.count) results."
    }

    private func runDirLoad() async {
        running = true
        statusMessage = "Running 10k-item dir load…"
        defer { running = false }

        let start = Date()
        await BenchScenarios.load10kItems()
        let elapsed = Date().timeIntervalSince(start) * 1000
        results.append(BenchResult(
            scenario: "10k-item dir load",
            durationMs: elapsed,
            targetMs: 200,
            targetDescription: "≤ 200 ms"
        ))
        BenchResult.write(results)
        statusMessage = "10k-item dir load: \(String(format: "%.1f", elapsed)) ms"
    }

    private func runFrames() async {
        running = true
        statusMessage = "Sampling animation frames…"
        defer { running = false }

        let report = await BenchScenarios.sampleAnimationFrames()
        results.append(BenchResult(
            scenario: "Animation frames (max frame ms)",
            durationMs: report.maxFrameMs,
            targetMs: 16.7,
            targetDescription: "≤ 16.7 ms (60fps)"
        ))
        BenchResult.write(results)
        statusMessage = "Max frame: \(String(format: "%.1f", report.maxFrameMs)) ms"
    }
}

struct BenchResult: Identifiable, Codable, Hashable {
    var id = UUID()
    let scenario: String
    let durationMs: Double
    let targetMs: Double
    let targetDescription: String
    var passes: Bool { durationMs <= targetMs }

    static func write(_ results: [BenchResult]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus/bench")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(results) {
            try? data.write(to: url)
        }
    }
}
#endif
