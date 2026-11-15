import RcloneKit
import SwiftUI

/// Asks where local files should go (a cloud and a folder) and starts the
/// copies. Reached from the Services menu's "Send to Nimbus…".
struct SendToNimbusSheet: View {
    let remoteNames: [String]
    let client: RcloneClient
    let onAddCloud: () -> Void
    /// Called with the destination once the copies have started.
    let onSent: (_ remote: String, _ path: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TransferStore.self) private var transferStore
    @State private var model: SendViewModel
    @State private var isBrowsing = false
    @State private var didSend = false

    init(
        request: SendRequest, remoteNames: [String], lastRemote: String?, lastPath: String?,
        client: RcloneClient, sendClient: (any SendClient)? = nil,
        onAddCloud: @escaping () -> Void, onSent: @escaping (String, String) -> Void
    ) {
        self.remoteNames = remoteNames
        self.client = client
        self.onAddCloud = onAddCloud
        self.onSent = onSent
        _model = State(initialValue: SendViewModel(
            request: request, remoteNames: remoteNames, lastRemote: lastRemote, lastPath: lastPath,
            client: sendClient ?? RcloneSendClient(client: client)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            Text("Send to Nimbus")
                .font(DesignSystem.Typography.titleEmphasized)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(model.request.summary)
                    .font(DesignSystem.Typography.bodyEmphasized)
                Text(model.request.nameList)
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if remoteNames.isEmpty {
                noClouds
            } else {
                destination
                if !model.clashes.isEmpty { clashes }
                if let error = model.error {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            footer
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 480)
        .onDisappear {
            // A cancelled share has no use for its staged copies.
            if !didSend, let inbox = model.request.inboxID, let container = AppGroup.containerURL {
                ShareInbox.remove(id: inbox, in: container)
            }
        }
        .sheet(isPresented: $isBrowsing) {
            FolderBrowserSheet(remote: model.remote, client: client) { chosen in
                model.path = chosen
            }
        }
    }

    private var noClouds: some View {
        Text("Add a cloud first, then send these again.")
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
    }

    private var destination: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Text("To")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Picker("Cloud", selection: $model.remote) {
                ForEach(remoteNames, id: \.self) { name in
                    Text(verbatim: name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: model.remote) { model.remoteChanged() }

            TextField("Top level", text: $model.path)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Folder")

            Button("Choose…") { isBrowsing = true }
                .buttonStyle(.glassCapsule)
        }
    }

    private var clashes: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(model.clashes.count == 1
                 ? "“\(model.clashes[0])” is already in that folder."
                 : "\(model.clashes.count) of these are already in that folder.")
                .font(DesignSystem.Typography.bodyEmphasized)
            if model.clashes.count > 1 {
                Text(model.clashes.prefix(5).joined(separator: ", ") + (model.clashes.count > 5 ? "…" : ""))
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(DesignSystem.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            if model.isWorking { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glassCapsule)
            if remoteNames.isEmpty {
                Button("Add Cloud…") {
                    dismiss()
                    onAddCloud()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryPill(.small))
            } else if model.clashes.isEmpty {
                Button("Send") { send(nil) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
                    .disabled(!model.canSend)
            } else {
                Button("Replace") { send(.replace) }
                    .buttonStyle(.glassCapsule)
                    .disabled(!model.canSend)
                Button("Keep Both") { send(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
                    .disabled(!model.canSend)
            }
        }
    }

    private func send(_ policy: SendClashPolicy?) {
        Task {
            if await model.send(policy: policy, store: transferStore) {
                didSend = true
                onSent(model.remote, model.path)
                dismiss()
            }
        }
    }
}
