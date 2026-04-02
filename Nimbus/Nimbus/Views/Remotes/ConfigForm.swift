import SwiftUI
import RcloneKit

struct ConfigForm: View {
    let options: [ProviderOption]
    @Binding var values: [String: String]
    @State private var showAdvanced = false

    var body: some View {
        let required = options.filter { $0.required && !$0.advanced }
        let basic = options.filter { !$0.required && !$0.advanced }
        let advanced = options.filter { $0.advanced }

        Form {
            if !required.isEmpty {
                Section("Required") {
                    ForEach(required) { option in
                        optionField(option)
                    }
                }
            }

            if !basic.isEmpty {
                Section("Optional") {
                    ForEach(basic) { option in
                        optionField(option)
                    }
                }
            }

            if !advanced.isEmpty {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    ForEach(advanced) { option in
                        optionField(option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionField(_ option: ProviderOption) -> some View {
        let binding = Binding<String>(
            get: { values[option.name] ?? option.defaultValue },
            set: { values[option.name] = $0 }
        )

        VStack(alignment: .leading, spacing: 4) {
            if option.isPassword {
                SecureField(option.name, text: binding, prompt: Text(option.help))
            } else if option.type == "bool" {
                Toggle(option.name, isOn: Binding<Bool>(
                    get: { (values[option.name] ?? option.defaultValue) == "true" },
                    set: { values[option.name] = String($0) }
                ))
            } else if let examples = option.examples, !examples.isEmpty {
                Picker(option.name, selection: binding) {
                    Text("Default").tag("")
                    ForEach(examples, id: \.value) { example in
                        Text("\(example.value) — \(example.help)").tag(example.value)
                    }
                }
            } else {
                TextField(option.name, text: binding, prompt: Text(option.help))
            }

            if !option.help.isEmpty {
                Text(option.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
