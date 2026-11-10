import SwiftUI
import RcloneKit

/// Renders one batched page of rclone config questions, plus the two mode
/// toggles. The questions come from rclone's own walk, so there is no
/// hand-maintained per-provider field list to keep in sync.
struct ConfigPageForm: View {
    let page: ConfigPage

    /// Whether toggling "Show all options" would change anything for the
    /// current backend. It is only ever meaningful for OAUTH backends
    /// (drive, dropbox, onedrive, box, pcloud), whose basic mode is
    /// `all:false` (name + Sign In) — toggling this reveals `client_id` /
    /// `client_secret` / `scope`.
    ///
    /// For CREDENTIAL backends (s3, sftp, b2, webdav) the flow's basic mode
    /// already uses `askAll: true`, because rclone's `all:false` asks them
    /// nothing and writes a broken stub remote. So for those backends
    /// toggling this row would delete the remote, re-walk, and land back on
    /// an identical page — a destructive no-op dressed up as a choice.
    /// Callers must pass `flow.isOAuthBackend == true` here; do NOT simplify
    /// this away and render the row unconditionally.
    let showAllOptionsIsMeaningful: Bool

    // Read-only: every write goes through `onAnswerChanged` (see
    // `binding(for:)` below), never by assigning back into this property, so
    // it is a plain value rather than a `@Binding` that could be written
    // through directly — bypassing `onAnswerChanged` and, with it, the
    // `Exclusive` re-walk (C7).
    let answers: [String: String]
    @Binding var showAllOptions: Bool
    @Binding var includeAdvanced: Bool
    let onAnswerChanged: (ConfigQuestion, String) -> Void

    private var visibleQuestions: [ConfigQuestion] {
        page.questions.filter { ConfigFieldView.shouldRender($0.option) }
    }

    private var showsAdvancedGate: Bool {
        if case .advancedGate = page.boundary { return true }
        return false
    }

    private var showsOptionsSection: Bool {
        showAllOptionsIsMeaningful || showsAdvancedGate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            if !visibleQuestions.isEmpty {
                FormSection(title: "Configuration", footer: nil) {
                    ForEach(visibleQuestions, id: \.option.name) { question in
                        FormRow(
                            label: LocalizedStringKey(ConfigFieldLabel.label(forOption: question.option.name)),
                            help: question.option.help.isEmpty
                                ? nil
                                : LocalizedStringKey(question.option.help)
                        ) {
                            ConfigFieldView(
                                option: question.option,
                                value: binding(for: question)
                            )
                        }
                    }
                }
            }

            if showsOptionsSection {
                FormSection(title: "Options", footer: nil) {
                    if showAllOptionsIsMeaningful {
                        FormRow(
                            label: "Show all options",
                            help: "Ask every question this service supports, not just the essentials."
                        ) {
                            Toggle("", isOn: $showAllOptions)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    if showsAdvancedGate {
                        FormRow(
                            label: "Edit advanced config",
                            help: "Tuning options most people never need."
                        ) {
                            Toggle("", isOn: $includeAdvanced)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
        }
    }

    private func binding(for question: ConfigQuestion) -> Binding<String> {
        Binding(
            get: { answers[question.option.name] ?? question.option.defaultValue },
            set: { onAnswerChanged(question, $0) }
        )
    }
}

// MARK: - Previews

// Decode-only fixtures, same pattern as the tests: `ProviderOption` has no
// public memberwise init, so options are built from the JSON shape rclone's
// `config/create` replies carry.
//
// These previews exist to verify what the SNAPSHOT tests cannot. The headless
// `ImageRenderer` behind `SnapshotHelpers` can't flatten TextField, SecureField
// or switch-style Toggle (see GuidedAddRemoteSnapshotTests' header), so a
// sensitive field's masking is simply invisible there. A hosted preview renders
// the real AppKit controls, which is the only place that masking can be seen.
private func previewQuestion(
    _ name: String, help: String, sensitive: Bool = false, examples: [String] = []
) -> ConfigQuestion {
    let exampleList = examples
        .map { #"{"Value":"\#($0)","Help":""}"# }
        .joined(separator: ",")
    let examplesJSON = examples.isEmpty ? "" : #", "Examples": [\#(exampleList)]"#
    let json = #"""
    {"Name": "\#(name)", "Help": "\#(help)", "Type": "string", "Required": false,
     "IsPassword": false, "Advanced": false, "Sensitive": \#(sensitive), "Hide": 0,
     "Exclusive": false, "Default": "", "DefaultStr": "", "Value": null\#(examplesJSON)}
    """#
    let option = try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    return ConfigQuestion(option: option, state: "s")
}

private func previewGate() -> ConfigQuestion {
    previewQuestion("config_fs_advanced", help: "")
}

/// Credential backend. `pass` is Sensitive, so it MUST render masked — and
/// "Show all options" must be absent, because the flow already runs askAll:true
/// for these backends and the toggle would be a destructive no-op.
#Preview("Credential (SFTP)") {
    ConfigPageForm(
        page: ConfigPage(
            questions: [
                previewQuestion("host", help: "SSH host to connect to."),
                previewQuestion("user", help: "SSH username."),
                previewQuestion("pass", help: "SSH password.", sensitive: true),
            ],
            boundary: .advancedGate(previewGate())
        ),
        showAllOptionsIsMeaningful: false,
        answers: ["host": "example.com", "user": "jon", "pass": "hunter2"],
        showAllOptions: .constant(false),
        includeAdvanced: .constant(false),
        onAnswerChanged: { _, _ in }
    )
    .frame(width: 520)
    .padding()
}

/// OAuth backend with the toggle shown. `client_secret` is Sensitive and must
/// render masked; `scope` carries Examples and must render as a Picker.
#Preview("OAuth, show-all on") {
    ConfigPageForm(
        page: ConfigPage(
            questions: [
                previewQuestion("client_id", help: "OAuth Client Id. Leave blank normally."),
                previewQuestion("client_secret", help: "OAuth Client Secret.", sensitive: true),
                previewQuestion("scope", help: "Scope rclone should use.",
                                examples: ["drive", "drive.readonly"]),
            ],
            boundary: .advancedGate(previewGate())
        ),
        showAllOptionsIsMeaningful: true,
        answers: ["client_secret": "s3cr3t"],
        showAllOptions: .constant(true),
        includeAdvanced: .constant(false),
        onAnswerChanged: { _, _ in }
    )
    .frame(width: 520)
    .padding()
}
