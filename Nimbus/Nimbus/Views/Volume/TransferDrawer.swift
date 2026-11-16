import SwiftUI

/// Bottom strip of the volume pane while anything is moving. Collapsible,
/// capped at four rows; the overflow link jumps to the Transfers tab.
struct TransferDrawer: View {
    var onShowAll: () -> Void
    @Environment(TransferStore.self) private var store
    @State private var collapsed = false

    private static let maxRows = 4

    var body: some View {
        let active = store.activeTransfers
        if !active.isEmpty {
            VStack(spacing: 0) {
                Divider()
                Button {
                    withAnimation(DesignSystem.Motion.snappy) { collapsed.toggle() }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        Text("Transfers")
                            .fontWeight(.medium)
                            .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                        Text(verbatim: summary(active))
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                            .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.l)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Transfers, \(active.count) active")
                .accessibilityHint(collapsed ? "Expands the transfer list" : "Collapses the transfer list")

                if !collapsed {
                    VStack(spacing: 0) {
                        ForEach(active.prefix(Self.maxRows)) { transfer in
                            TransferRow(transfer: transfer)
                                .padding(.horizontal, DesignSystem.Spacing.l)
                        }
                        if active.count > Self.maxRows {
                            Button("\(active.count - Self.maxRows) more…", action: onShowAll)
                                .buttonStyle(.plain)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Color.semantic.accent)
                                .padding(.vertical, DesignSystem.Spacing.xs)
                        }
                    }
                    .padding(.bottom, DesignSystem.Spacing.xs)
                    .transition(.opacity)
                }
            }
            .background(DesignSystem.Color.semantic.surfaceSubtle.opacity(0.45))
        }
    }

    private func summary(_ active: [Transfer]) -> String {
        let speed = active.compactMap(\.speed).reduce(0, +)
        var text = "· \(active.count) active"
        if speed > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            text += " · \(formatter.string(fromByteCount: speed))/s"
        }
        return text
    }
}
