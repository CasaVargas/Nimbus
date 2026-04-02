import SwiftUI

struct TransferRow: View {
    let transfer: Transfer
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Image(systemName: transfer.operation == .copy ? "doc.on.doc" : "arrow.triangle.2.circlepath")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(transfer.srcFs) → \(transfer.dstFs)")
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    statusBadge
                    if let completedAt = transfer.completedAt {
                        Text(completedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if case .active = transfer.status {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch transfer.status {
        case .active:
            Label("Active", systemImage: "arrow.up.arrow.down")
                .font(.caption)
                .foregroundStyle(.blue)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
