import SwiftUI

struct TransferRow: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: displayName)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: subtitleText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            trailing
                .frame(minWidth: 100, maxWidth: 200)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    @ViewBuilder
    private var trailing: some View {
        switch transfer.status {
        case .active:
            ProgressMeter(
                progress: transfer.progress,
                speed: nil,
                eta: nil
            )
        case .completed:
            statusPill(text: "● Done", tint: DesignSystem.Color.semantic.statusOK)
        case .failed(let message):
            statusPill(text: "! Error", tint: DesignSystem.Color.semantic.statusError)
                .help(message)
        case .cancelled:
            statusPill(text: "⌀ Cancelled", tint: DesignSystem.Color.semantic.textTertiary)
        }
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(DesignSystem.Typography.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                tint.opacity(0.18),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
            )
            .foregroundStyle(tint)
    }

    private var iconName: String {
        switch transfer.operation {
        case .copy: return "doc.on.doc"
        case .sync: return "arrow.triangle.2.circlepath"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }

    private var displayName: String {
        // dstFs is typically "remote:path/to/file"; show the leaf name.
        let leaf = (transfer.dstFs as NSString).lastPathComponent
        return leaf.isEmpty ? transfer.dstFs : leaf
    }

    private var subtitleText: String {
        "\(transfer.srcFs) → \(transfer.dstFs)"
    }
}
