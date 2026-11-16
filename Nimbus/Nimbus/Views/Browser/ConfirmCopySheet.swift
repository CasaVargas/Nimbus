import SwiftUI

/// Pending cross-remote copy request surfaced after a drop. The host view
/// binds this to `.sheet(item:)`, and `ConfirmCopySheet` mutates the conflict
/// policy in place before the user confirms.
struct CopyRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceRemote: String
    let target: DropIntent.DropTarget
    let items: [DropIntent.Item]
    var conflictPolicy: ConflictPolicy

    init(
        sourceRemote: String,
        target: DropIntent.DropTarget,
        items: [DropIntent.Item],
        conflictPolicy: ConflictPolicy
    ) {
        self.sourceRemote = sourceRemote
        self.target = target
        self.items = items
        self.conflictPolicy = conflictPolicy
    }

    static func == (lhs: CopyRequest, rhs: CopyRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// Modal confirmation surfaced when the user drops items from one remote onto
/// another. Shows source/target/item summary and lets the user pick a conflict
/// policy before the underlying `DragDropCoordinator` enqueues the work.
struct ConfirmCopySheet: View {
    @Binding var request: CopyRequest?
    let onCopy: (CopyRequest) -> Void

    var body: some View {
        if let req = request {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                Text("Copy \(req.items.count) item\(req.items.count == 1 ? "" : "s")?")
                    .font(DesignSystem.Typography.titleEmphasized)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                    row(label: "Source", value: "\(req.sourceRemote):")
                    row(label: "Target", value: "\(req.target.remote):\(req.target.path)")
                    row(label: "Items",  value: "\(req.items.count) items · \(formatTotal(req.items))")
                }
                .padding(DesignSystem.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                )

                if req.items.count <= 5 {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(req.items.prefix(5), id: \.path) { item in
                            Text("• \(item.name) (\(formatSize(item.size)))")
                                .font(DesignSystem.Typography.callout)
                                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        }
                    }
                }

                Picker("If a file exists:", selection: bindingPolicy()) {
                    Text("Rename").tag(ConflictPolicy.rename)
                    Text("Skip").tag(ConflictPolicy.skip)
                    Text("Overwrite").tag(ConflictPolicy.overwrite)
                }
                .pickerStyle(.radioGroup)
                .font(DesignSystem.Typography.body)

                HStack {
                    Spacer()
                    Button("Cancel") { request = nil }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glassCapsule)
                    Button("Copy") {
                        onCopy(req)
                        request = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(minWidth: 460)
        } else {
            EmptyView()
        }
    }

    private func bindingPolicy() -> Binding<ConflictPolicy> {
        Binding(
            get: { request?.conflictPolicy ?? .rename },
            set: { request?.conflictPolicy = $0 }
        )
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.m) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(DesignSystem.Typography.body)
                .textSelection(.enabled)
        }
    }

    private func formatTotal(_ items: [DropIntent.Item]) -> String {
        let total = items.reduce(0) { $0 + $1.size }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: total)
    }

    private func formatSize(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}
