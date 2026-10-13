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

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.l) {
            ProviderBadge(provider: provider.prefix, size: 48)

            Text(verbatim: provider.description)
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)

            if isWaiting {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for your browser…")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Button("Cancel", action: onCancel)
                    .accessibilityHint("Stops waiting and discards the partial remote.")
            } else {
                Button("Sign In", action: onSignIn)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Opens your browser. Nimbus never sees your password.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Sign in to \(provider.description)"))
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
