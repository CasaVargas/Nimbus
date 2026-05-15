import SwiftUI
import RcloneKit

struct EditRemoteSheet: View {
    let client: RcloneClient
    let remote: Remote
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider: Provider?
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var error: NimbusError?
    @State private var loading = true

    var body: some View {
        SheetChrome(
            title: "Edit Remote",
            subtitle: LocalizedStringKey(remote.name),
            body: {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let provider {
                    // ConfigForm renders an editable Name row by default. We don't want that
                    // here — the remote name is the identifier and can't be changed. Render
                    // a custom locked-name section + the configuration-only fields below.
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                        FormSection(title: "Remote", footer: "The remote name is fixed once created.") {
                            FormRow(label: "Name", help: nil) {
                                Text(remote.name)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                                    .frame(maxWidth: 240, alignment: .trailing)
                                    .textSelection(.enabled)
                            }
                        }
                        configurationOnlyForm(provider: provider)
                    }
                } else {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "Provider Not Found",
                        messageVerbatim: "The provider type '\(remote.type)' isn't recognised by this rclone build.",
                        action: nil
                    )
                }
            },
            actions: {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving || provider == nil)
            }
        )
        .frame(minWidth: 520, minHeight: 440)
        .task {
            do {
                let providers = try await client.getProviders()
                provider = providers.first(where: { $0.name == remote.type })
                values = remote.config
            } catch {
                self.error = NimbusError.classify(error)
            }
            loading = false
        }
        .alert(
            "Couldn't save remote",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(verbatim: err.message)
        }
    }

    /// Renders the provider's Configuration + Advanced FormSections, omitting the
    /// Name row that `ConfigForm` would otherwise render. Mirrors `ConfigForm` body
    /// but skips the Remote section.
    @ViewBuilder
    private func configurationOnlyForm(provider: Provider) -> some View {
        let nonAdvanced = provider.options.filter { !$0.advanced }
        let advanced = provider.options.filter { $0.advanced }

        if !nonAdvanced.isEmpty {
            // option.name / option.help are runtime strings from rclone; same Phase 2a
            // LocalizedStringKey trade-off as ConfigForm.
            FormSection(
                title: "Configuration",
                footer: provider.description.isEmpty ? nil : LocalizedStringKey(provider.description)
            ) {
                ForEach(nonAdvanced) { option in
                    formRow(for: option)
                }
            }
        }
        if !advanced.isEmpty {
            FormSection(title: "Advanced", footer: "Optional for most users.") {
                ForEach(advanced) { option in
                    formRow(for: option)
                }
            }
        }
    }

    private func formRow(for option: ProviderOption) -> some View {
        FormRow(
            label: LocalizedStringKey(option.name),
            help: option.help.isEmpty ? nil : LocalizedStringKey(option.help)
        ) {
            field(for: option)
        }
    }

    @ViewBuilder
    private func field(for option: ProviderOption) -> some View {
        if option.isPassword {
            SecureField(option.defaultValue, text: binding(for: option.name))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        } else if let examples = option.examples, !examples.isEmpty {
            Picker("", selection: binding(for: option.name)) {
                Text("Choose…").tag("")
                ForEach(examples, id: \.value) { ex in
                    Text(verbatim: ex.value).tag(ex.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        } else if option.type == "bool" {
            Toggle("", isOn: Binding(
                get: { (values[option.name] ?? option.defaultValue).lowercased() == "true" },
                set: { values[option.name] = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        } else {
            TextField(option.defaultValue, text: binding(for: option.name))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await client.updateRemote(name: remote.name, parameters: values)
            onDismiss()
            dismiss()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
