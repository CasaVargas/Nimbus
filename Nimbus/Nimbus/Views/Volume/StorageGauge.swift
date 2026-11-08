import SwiftUI

/// Used-versus-free bar for a volume. Reference: Disk Utility's capacity
/// bar and About This Mac › Storage. Only rendered when the backend reports
/// a total; the caller checks `quota.fraction != nil`.
struct StorageGauge: View {
    let quota: StorageQuota

    private var tint: Color {
        quota.isNearlyFull ? DesignSystem.Color.semantic.statusWarning : DesignSystem.Color.semantic.accent
    }

    var body: some View {
        let fraction = quota.fraction ?? 0
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignSystem.Color.semantic.surfaceSubtle)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 10)

            HStack(spacing: DesignSystem.Spacing.l) {
                legend(color: tint, text: "Used \(quota.usedText ?? "--")")
                legend(color: DesignSystem.Color.semantic.separator, text: "Free \(quota.freeText ?? "--")")
                Spacer()
                Text("\(Int((fraction * 100).rounded()))% full")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage: \(quota.usedText ?? "unknown") used of \(quota.totalText ?? "unknown")")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.xs, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Radius.xs).strokeBorder(DesignSystem.Color.semantic.separator.opacity(0.5), lineWidth: 0.5))
            Text(verbatim: text)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        }
    }
}

#Preview {
    VStack {
        StorageGauge(quota: StorageQuota(used: 1_280_000_000_000, total: 2_000_000_000_000))
        StorageGauge(quota: StorageQuota(used: 911_000_000_000, total: 1_000_000_000_000))
    }
    .frame(width: 640)
    .padding(.bottom)
}
