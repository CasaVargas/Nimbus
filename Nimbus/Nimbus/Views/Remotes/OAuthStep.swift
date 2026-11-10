import SwiftUI
import RcloneKit

/// The sign-in step for OAuth backends. rclone owns the browser handoff: it
/// binds 127.0.0.1:53682 and opens the user's browser itself, which works
/// because Nimbus is not sandboxed. The RC call blocks until the callback
/// arrives, so this view is mostly a waiting state with a working Cancel.
struct OAuthStep: View {
    let provider: Provider
    let isWaiting: Bool
    let onSignIn: () -> Void
    let onCancel: () -> Void

    @Environment(\.stratosphere) private var palette

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.l) {
            // The service's logo in a soft halo: the one thing on this step.
            LogoTile(provider: provider.prefix, size: .hero)
                .padding(38)
                .background {
                    Circle().fill(RadialGradient(
                        colors: [palette.actionTop.color.opacity(0.55), palette.actionTop.color.opacity(0)],
                        center: .center, startRadius: 30, endRadius: 84
                    ))
                }
                .overlay(Circle().strokeBorder(palette.glassBorder.color, lineWidth: 1))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(verbatim: "Sign in to \(PickerCatalog.title(forPrefix: provider.prefix) ?? provider.description)")
                    .font(DesignSystem.Stratosphere.Typography.sheetTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .multilineTextAlignment(.center)
                Text("Nimbus opens the service in your browser. It never sees your password.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(palette.textSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }

            if isWaiting {
                HStack(spacing: DesignSystem.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your browser…")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(palette.textSecondary.color)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.glassCapsule)
                    .accessibilityHint("Stops waiting and discards the partial remote.")
            } else {
                Button("Sign In", action: onSignIn)
                    .buttonStyle(.primaryPill)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Sign in to \(provider.description)"))
    }
}

/// A question rclone asks after sign-in, in plain words: choices as cards,
/// or a field when the answer has to be typed.
struct FollowUpQuestion: View {
    let providerPrefix: String
    let question: ConfigQuestion
    let value: String
    let onChange: (String) -> Void

    @Environment(\.stratosphere) private var palette

    var body: some View {
        let copy = ConfigQuestionCopy.copy(for: question.option)
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            HStack(spacing: DesignSystem.Spacing.m) {
                LogoTile(provider: providerPrefix)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Signed in", systemImage: "checkmark")
                        .font(DesignSystem.Stratosphere.Typography.segment)
                        .foregroundStyle(palette.ok.color)
                    Text(verbatim: copy.title)
                        .font(DesignSystem.Stratosphere.Typography.sheetTitle)
                        .foregroundStyle(palette.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            if copy.choices.isEmpty {
                ConfigFieldView(option: question.option, value: Binding(get: { value }, set: onChange))
            } else {
                ForEach(copy.choices) { choice in
                    ChoiceCard(title: choice.title, detail: choice.detail,
                               isSelected: choice.value == value,
                               onSelect: { onChange(choice.value) })
                }
            }
            Text("You can change this later in the cloud's settings.")
                .font(DesignSystem.Stratosphere.Typography.detail)
                .foregroundStyle(palette.textTertiary.color)
        }
    }
}

// Previews use the same decode-only fixture pattern as the tests: `Provider`
// has no public memberwise init, so it is built from the JSON shape rclone's
// `config/providers` returns.
private func previewProvider(_ name: String, _ description: String) -> Provider {
    let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
    return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
}

#Preview("Sign in") {
    OAuthStep(
        provider: previewProvider("drive", "Google Drive"),
        isWaiting: false,
        onSignIn: {},
        onCancel: {}
    )
    .frame(width: 520)
    .padding()
    .background(DesignSystem.Stratosphere.Palette.dark.sheetTop.color)
    .preferredColorScheme(.dark)
}

#Preview("Waiting for browser") {
    OAuthStep(
        provider: previewProvider("drive", "Google Drive"),
        isWaiting: true,
        onSignIn: {},
        onCancel: {}
    )
    .frame(width: 520)
    .padding()
}

#if DEBUG
private func previewQuestion() -> ConfigQuestion {
    let json = #"""
    {"Name": "config_change_team_drive", "Help": "Configure this as a Shared Drive (Team Drive)?\n", "Type": "bool",
     "Required": false, "IsPassword": false, "Advanced": false, "Sensitive": false, "Hide": 0, "Exclusive": true,
     "Default": false, "DefaultStr": "false", "Value": null,
     "Examples": [{"Value": "true", "Help": "Yes"}, {"Value": "false", "Help": "No"}]}
    """#
    let option = try! JSONDecoder().decode(ProviderOption.self, from: Data(json.utf8))
    return ConfigQuestion(option: option, state: "teamdrive_ok")
}

/// Step 3 as the sheet shows it, before and after the browser round-trip.
#Preview("Sheet: sign in", traits: .fixedLayout(width: 600, height: 600)) {
    SheetChrome(title: "Add Cloud", subtitle: nil, body: {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 2)
            OAuthStep(provider: previewProvider("drive", "Google Drive"), isWaiting: false, onSignIn: {}, onCancel: {})
        }
    }, actions: {
        Button("Cancel") {}.buttonStyle(.glassCapsule)
    })
    .preferredColorScheme(.dark)
}

#Preview("Sheet: follow-up question", traits: .fixedLayout(width: 600, height: 600)) {
    @Previewable @State var value = "false"
    SheetChrome(title: "Add Cloud", subtitle: nil, body: {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 2)
            FollowUpQuestion(providerPrefix: "drive", question: previewQuestion(), value: value, onChange: { value = $0 })
        }
    }, actions: {
        Button("Cancel") {}.buttonStyle(.glassCapsule)
        Button("Continue") {}.buttonStyle(.primaryPill(.small))
    })
    .preferredColorScheme(.dark)
}
#endif
