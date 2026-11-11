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
                speed: transfer.speed,
                eta: transfer.eta
            )
        case .completed:
            completedPill
        case .failed(let message):
            if transfer.verification == .mismatch {
                statusPill(text: "Checksum mismatch", systemImage: "exclamationmark.triangle.fill",
                           tint: DesignSystem.Color.semantic.statusError)
                    .help(Self.mismatchHelp(message))
            } else {
                statusPill(text: "Error", systemImage: "exclamationmark.triangle.fill",
                           tint: DesignSystem.Color.semantic.statusError)
                    .help(message)
            }
        case .cancelled:
            statusPill(text: "Cancelled", systemImage: "slash.circle",
                       tint: DesignSystem.Color.semantic.textTertiary)
        }
    }

    /// #75: the pill says which check rclone ran. Positive states appear
    /// only on success, and an unknown check keeps plain "Done".
    @ViewBuilder
    private var completedPill: some View {
        switch transfer.verification {
        case .verified(let hash):
            statusPill(text: "Verified", systemImage: "checkmark.seal.fill",
                       tint: DesignSystem.Color.semantic.statusOK)
                .help(Self.verifiedHelp(hash: hash))
        case .sizeOnly:
            statusPill(text: "Size checked", systemImage: "checkmark.circle",
                       tint: DesignSystem.Color.semantic.textSecondary)
                .help(Self.sizeOnlyHelp)
        case .mismatch, nil:
            statusPill(text: "Done", systemImage: "checkmark.circle.fill",
                       tint: DesignSystem.Color.semantic.statusOK)
        }
    }

    static func verifiedHelp(hash: String) -> String {
        let name = TransferVerification.displayName(ofHash: hash)
        return String(localized: "rclone compared \(name) checksums on both sides. A file the service stores without a checksum is checked by size only.")
    }

    static let sizeOnlyHelp = String(localized: "These two locations have no checksum type in common, so rclone confirmed file sizes only.")

    static func mismatchHelp(_ message: String) -> String {
        String(localized: "A copied file didn't match the original's checksum, so rclone removed the bad copy. Try the transfer again.") + "\n\n" + message
    }

    private func statusPill(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
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
        if transfer.backup != nil { return "clock.arrow.circlepath" }
        switch transfer.operation {
        case .copy: return "doc.on.doc"
        case .sync: return "arrow.triangle.2.circlepath"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }

    private var displayName: String {
        if let title = transfer.backup?.title, !title.isEmpty { return title }
        // dstFs is typically "remote:path/to/file"; show the leaf name.
        let leaf = (transfer.dstFs as NSString).lastPathComponent
        return leaf.isEmpty ? transfer.dstFs : leaf
    }

    private var subtitleText: String {
        "\(transfer.srcFs) → \(transfer.dstFs)"
    }
}
