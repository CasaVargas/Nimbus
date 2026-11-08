import SwiftUI
import RcloneKit

/// Read-only view of the remote's rclone configuration plus the two things
/// you can do to it: edit, or remove it from Nimbus.
struct VolumeSettingsTab: View {
    let remote: Remote
    let onEdit: () -> Void

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService
    @State private var confirmRemove = false
    @State private var isRemoving = false

    /// Config keys that are safe to show. Anything that smells like a
    /// credential is hidden even though rclone stores it in plain text.
    private static let secretFragments = ["token", "pass", "secret", "key", "client_id", "credentials"]

    private var visibleKeys: [String] {
        remote.config.keys
            .filter { key in
                key != "type" && !Self.secretFragments.contains { key.lowercased().contains($0) }
            }
            .sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                FormSection(title: "Configuration", footer: "Tokens, passwords, and keys are never shown here.") {
                    FormRow(label: "Type", help: nil) {
                        Text(verbatim: remote.type)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    }
                    ForEach(visibleKeys, id: \.self) { key in
                        FormRow(label: LocalizedStringKey(key), help: nil) {
                            Text(verbatim: remote.config[key] ?? "")
                                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 320, alignment: .trailing)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Edit Configuration…", action: onEdit)
                    }
                    .padding(.top, DesignSystem.Spacing.xs)
                }

                FormSection(title: "Remove", footer: "Removes this volume from Nimbus and from rclone's configuration. Files in the cloud are not affected.") {
                    HStack {
                        Spacer()
                        Button("Remove Volume…", role: .destructive) { confirmRemove = true }
                            .disabled(isRemoving)
                    }
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Remove \(remote.name)?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the remote configuration. Files on the cloud are not affected.")
        }
    }

    private func remove() async {
        isRemoving = true
        defer { isRemoving = false }
        let viewModel = RemotesViewModel(client: daemon.client)
        await viewModel.deleteRemote(name: remote.name)
        statusService.clear(remote.name)
        NotificationCenter.default.post(name: .nimbusRemotesChanged, object: nil)
    }
}
