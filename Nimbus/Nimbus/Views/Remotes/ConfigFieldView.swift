import SwiftUI
import RcloneKit

/// Renders one rclone provider option as its appropriate input control.
///
/// Shared by `ConfigPageForm` (Add) and `EditRemoteSheet` (Edit) — the two
/// carried duplicate copies of this logic, and both needed the `Sensitive`
/// fix, so there is one copy now.
struct ConfigFieldView: View {
    let option: ProviderOption
    @Binding var value: String

    /// rclone flags credentials two different ways: `IsPassword` for things
    /// it obscures in the config file, `Sensitive` for things that merely
    /// shouldn't be shoulder-surfed (SFTP key passphrases, API secrets).
    /// Both deserve a SecureField.
    static func isSecure(_ option: ProviderOption) -> Bool {
        option.isPassword || option.sensitive
    }

    /// Non-zero `Hide` means rclone considers the option internal.
    static func shouldRender(_ option: ProviderOption) -> Bool {
        option.hide == 0
    }

    /// An unanswered option is an EMPTY string, not "false". Falling back to
    /// rclone's own default is what makes a default-true bool render ON when
    /// the user has never touched it — `config/dump` only persists keys that
    /// were explicitly set, so "absent" means "default", not "off".
    static func isOn(_ raw: String, option: ProviderOption) -> Bool {
        (raw.isEmpty ? option.defaultValue : raw).lowercased() == "true"
    }

    private var placeholder: String {
        option.defaultStr.isEmpty ? option.defaultValue : option.defaultStr
    }

    var body: some View {
        if Self.isSecure(option) {
            SecureField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        } else if let examples = option.examples, !examples.isEmpty {
            Picker("", selection: $value) {
                Text("Choose…").tag("")
                ForEach(examples, id: \.value) { example in
                    Text(verbatim: example.value).tag(example.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        } else if option.type == "bool" {
            Toggle("", isOn: Binding(
                get: { Self.isOn(value, option: option) },
                set: { value = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        } else {
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
    }
}
