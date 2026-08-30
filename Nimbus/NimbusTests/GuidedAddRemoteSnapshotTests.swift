import Testing
import SwiftUI
import Foundation
import RcloneKit
@testable import Nimbus

/// Snapshot coverage for the three page shapes the guided Add Remote flow
/// renders. `Provider`/`ProviderOption` have no public memberwise init
/// (decode-only), so fixtures decode the same JSON shape rclone's
/// `config/providers` and `config/create` responses return — same pattern as
/// `ProviderPickerTests`.
///
/// KNOWN RENDERING GAP — READ BEFORE TRUSTING A GREEN RUN HERE:
/// On this toolchain (macOS 27.0 beta, build 26A5421a / Xcode 27.0 beta,
/// build 27A5237l — confirmed via `sw_vers` / `xcodebuild -version`),
/// `SnapshotHelpers`'s
/// `ImageRenderer` cannot flatten `TextField`, `SecureField`, or
/// switch-style `Toggle` — each renders as an opaque yellow ⊘ placeholder
/// instead of its real content. Console confirms the cause: "Unable to
/// render flattened version of PlatformViewRepresentableAdaptor<...>" for
/// `PlatformTextFieldAdaptor` / `SecureFieldAdaptor` / `Switch`.
///
/// Consequence: `AddRemote-credential-basic` and `AddRemote-showall-s3` pin
/// STRUCTURE only — section headers, field labels, help text, row count and
/// ordering, and which of the two options toggles are present (the absence
/// of "Show all options" here is the visual proof that
/// `showAllOptionsIsMeaningful: false` correctly hides it for a credential
/// backend). They do NOT pin field content, and in particular do NOT prove
/// `pass` / `secret_access_key` render masked — the placeholder replaces
/// that content entirely. Masking is instead covered by
/// `ConfigFieldViewTests`, which asserts `ConfigFieldView.isSecure` directly
/// against `isPassword`/`sensitive` — a stronger, environment-independent
/// check than a pixel comparison would be here anyway.
///
/// This is pre-existing, not introduced by this file: the already-committed
/// `Fixtures/MountRow-off.png` (via `StatusToggle`'s real `Toggle(.switch)`)
/// shows the identical placeholder, and `MountRowTests` passes against it
/// today.
///
/// If these ever fail on a different toolchain, check whether `ImageRenderer`
/// has started rendering form controls there before assuming a UI
/// regression — a real fix (rendering through an actual `NSWindow` instead
/// of bare `ImageRenderer`) would change every fixture under `Fixtures/`,
/// not just these three, and is tracked as follow-up work rather than done
/// here.
@Suite("GuidedAddRemote", .serialized)
@MainActor
struct GuidedAddRemoteSnapshotTests {

    private func question(
        _ name: String, help: String = "", type: String = "string",
        sensitive: Bool = false, examples: String? = nil
    ) -> ConfigQuestion {
        let examplesJSON = examples.map { #", "Examples": \#($0)"# } ?? ""
        let json = #"""
        {"Name": "\#(name)", "Help": "\#(help)", "Type": "\#(type)",
         "Required": false, "IsPassword": false, "Advanced": false,
         "Sensitive": \#(sensitive), "Hide": 0, "Exclusive": false,
         "Default": "", "DefaultStr": "", "Value": null\#(examplesJSON)}
        """#
        let option = try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
        return ConfigQuestion(option: option, state: "s")
    }

    private func provider(_ name: String, _ description: String) -> Provider {
        let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
        return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
    }

    private func form(_ page: ConfigPage, showAllOptionsIsMeaningful: Bool) -> some View {
        ConfigPageForm(
            page: page,
            showAllOptionsIsMeaningful: showAllOptionsIsMeaningful,
            answers: [:],
            showAllOptions: .constant(false),
            includeAdvanced: .constant(false),
            onAnswerChanged: { _, _ in }
        )
        .frame(width: 520)
        .padding()
    }

    @Test func oauthBasicShape() throws {
        let view = OAuthStep(
            provider: provider("drive", "Google Drive"),
            isWaiting: false,
            onSignIn: {},
            onCancel: {}
        )
        .frame(width: 520)
        .padding()
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 552, height: 320), named: "AddRemote-oauth-basic"
        )
    }

    @Test func credentialBasicShape() throws {
        let page = ConfigPage(
            questions: [
                question("host", help: "SSH host to connect to."),
                question("user", help: "SSH username."),
                question("port", help: "SSH port number."),
                question("pass", help: "SSH password.", sensitive: true),
            ],
            boundary: .advancedGate(question("config_fs_advanced"))
        )
        try SnapshotHelpers.assertSnapshot(
            form(page, showAllOptionsIsMeaningful: false),
            size: CGSize(width: 552, height: 560), named: "AddRemote-credential-basic"
        )
    }

    @Test func showAllShape() throws {
        let page = ConfigPage(
            questions: [
                question("provider", help: "Choose your S3 provider.",
                         examples: #"[{"Value":"AWS","Help":"Amazon Web Services"}]"#),
                question("access_key_id", help: "AWS Access Key ID."),
                question("secret_access_key", help: "AWS Secret Access Key.", sensitive: true),
                question("region", help: "Region to connect to.",
                         examples: #"[{"Value":"us-east-1","Help":"US East"}]"#),
                question("endpoint", help: "Endpoint for S3 API."),
            ],
            boundary: .advancedGate(question("config_fs_advanced"))
        )
        try SnapshotHelpers.assertSnapshot(
            form(page, showAllOptionsIsMeaningful: false),
            size: CGSize(width: 552, height: 640), named: "AddRemote-showall-s3"
        )
    }
}
