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
    /// it obscures in the config file, `Sensitive` for things it redacts from
    /// logs and `config dump` (SFTP key passphrases, API secrets). Both
    /// deserve a SecureField — except that `Sensitive` also covers account
    /// identifiers (iCloud's `apple_id`, SFTP/SMB `host` and `user`, Mega's
    /// `user`), and masking those means you can't see what you typed (#162).
    static func isSecure(_ option: ProviderOption) -> Bool {
        if option.isPassword { return true }
        return option.sensitive && !isIdentifier(option)
    }

    /// `Sensitive` options that name who or where, not a secret. Matched on
    /// the option name: rclone has no flag for this distinction.
    static let identifierNames: Set<String> = [
        "apple_id", "user", "username", "email", "host", "url",
        "domain", "namenode", "plex_username", "cloud_name",
    ]

    static func isIdentifier(_ option: ProviderOption) -> Bool {
        identifierNames.contains(option.name)
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

    /// Lets the user check a masked value they typed. Never persisted: every
    /// field starts masked again.
    @State private var isRevealed = false

    var body: some View {
        if Self.isSecure(option) {
            HStack(spacing: 4) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $value)
                    } else {
                        SecureField(placeholder, text: $value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide" : "Show")
                .accessibilityLabel(isRevealed ? "Hide value" : "Show value")
            }
            .frame(maxWidth: 240)
        } else if let examples = option.examples, !examples.isEmpty {
            Picker("", selection: $value) {
                Text("Choose…").tag("")
                ForEach(examples, id: \.value) { example in
                    Text(verbatim: ConfigFieldLabel.choiceLabel(value: example.value, help: example.help))
                        .tag(example.value)
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
