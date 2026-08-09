import SwiftUI
import RcloneKit

/// Renders an rclone provider's config fields as FormSections.
/// Each field becomes a FormRow with appropriate trailing input.
///
/// Note: `option.name` and `option.help` come from rclone at runtime, but
/// `FormRow.label` / `help` accept `LocalizedStringKey`. For Phase 2a we
/// accept this — `option.name` strings are stable identifiers ("region",
/// "endpoint") and `option.help` is English help text from rclone itself.
/// Phase 3 will revisit when rclone error/help mapping is improved.
struct ConfigForm: View {
    let provider: Provider
    @Binding var name: String
    @Binding var values: [String: String]

    private var nonAdvancedOptions: [ProviderOption] {
        provider.options.filter { !$0.advanced }
    }

    private var advancedOptions: [ProviderOption] {
        provider.options.filter { $0.advanced }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            // Identity header: the same badge + name the user just clicked in
            // ProviderPicker, so the config step stays visually anchored to
            // the chosen service.
            HStack(spacing: DesignSystem.Spacing.m) {
                ProviderBadge(provider: provider.prefix, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: provider.description)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                    Text(verbatim: provider.name)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
            }

            FormSection(title: "Remote", footer: nil) {
                FormRow(label: "Name", help: "Used to reference this remote in the Browser.") {
                    TextField("e.g. gdrive", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
            }
            if !nonAdvancedOptions.isEmpty {
                FormSection(
                    title: "Configuration",
                    footer: provider.description.isEmpty ? nil : LocalizedStringKey(provider.description)
                ) {
                    ForEach(nonAdvancedOptions) { option in
                        formRow(for: option)
                    }
                }
            }
            if !advancedOptions.isEmpty {
                FormSection(title: "Advanced", footer: "Optional for most users.") {
                    ForEach(advancedOptions) { option in
                        formRow(for: option)
                    }
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
}
