import SwiftUI

/// Linear progress bar with optional speed + ETA caption.
/// Used in TransferRow where StatusBadge's ring is too small.
/// Accent tint matches StatusBadge's downloading ring — progress is normal
/// activity, not a warning, so it must not read orange.
struct ProgressMeter: View {
    let progress: Double      // 0.0 ... 1.0 (clamped)
    let speed: Int64?         // bytes per second
    let eta: TimeInterval?    // remaining seconds

    var clampedProgress: Double { max(0, min(1, progress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)
                .tint(DesignSystem.Color.semantic.accent)

            if speed != nil || eta != nil {
                HStack(spacing: DesignSystem.Spacing.s) {
                    if let speed {
                        Text(verbatim: "\(formatBytes(speed))/s")
                    }
                    if let eta {
                        Text(verbatim: formatETA(eta))
                    }
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress \(Int((clampedProgress * 100).rounded())) percent")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var pieces: [String] = []
        if let speed { pieces.append("\(formatBytes(speed)) per second") }
        if let eta { pieces.append("\(Int(eta)) seconds remaining") }
        return pieces.joined(separator: ", ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s" }
        return "\(Int(seconds / 3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }
}

#Preview("ProgressMeter states") {
    VStack(alignment: .leading, spacing: 16) {
        ProgressMeter(progress: 0.0, speed: nil, eta: nil)
        ProgressMeter(progress: 0.25, speed: 750_000, eta: 45)
        ProgressMeter(progress: 0.5, speed: 1_500_000, eta: 12)
        ProgressMeter(progress: 0.85, speed: 3_200_000, eta: 4)
        ProgressMeter(progress: 1.0, speed: nil, eta: nil)
    }
    .frame(width: 240)
    .padding()
}
