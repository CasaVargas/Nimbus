import SwiftUI

/// Toolbar capsule shown while transfers run, like Finder's copy progress
/// indicator. Click opens the Transfers tab.
struct TransferPillView: View {
    var onTap: () -> Void
    @Environment(TransferStore.self) private var store

    var body: some View {
        let active = store.activeTransfers
        if let first = active.first {
            Button(action: onTap) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Image(systemName: "arrow.up.arrow.down")
                        .imageScale(.small)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Text(verbatim: label(active, first: first))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                        .lineLimit(1)
                    ProgressView(value: average(active))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                }
                .padding(.horizontal, DesignSystem.Spacing.s)
                .frame(height: 24)
                .background(Capsule().fill(DesignSystem.Color.semantic.surfaceSubtle))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Show transfers")
            .accessibilityLabel(label(active, first: first))
        }
    }

    private func label(_ active: [Transfer], first: Transfer) -> String {
        let dest = first.dstFs.split(separator: ":", maxSplits: 1).first.map(String.init) ?? first.dstFs
        return active.count == 1 ? "1 item to \(dest)" : "\(active.count) items to \(dest)"
    }

    private func average(_ active: [Transfer]) -> Double {
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }
}
