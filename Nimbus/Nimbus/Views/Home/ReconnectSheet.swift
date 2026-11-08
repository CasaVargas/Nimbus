import SwiftUI
import RcloneKit

/// "Sign in to <Provider> again" — the fix behind Home's needs-sign-in banner.
/// rclone opens the browser itself; this sheet is a short explanation, a
/// waiting state with a working Cancel, and a clear result.
struct ReconnectSheet: View {
    let row: CloudSummary.Row
    let onFinished: () -> Void
    let onOpenCloud: () -> Void

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(\.dismiss) private var dismiss
    @State private var flow: ReconnectFlow?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.l) {
            ProviderBadge(provider: row.providerType, size: 48)
            Text(verbatim: "Sign in to \(row.providerName) again")
                .font(DesignSystem.Typography.titleEmphasized)
                .multilineTextAlignment(.center)
            content
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 440)
        .onAppear {
            if flow == nil { flow = ReconnectFlow(remoteName: row.name, client: daemon.client) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow?.phase ?? .ready {
        case .ready:
            message("\(row.name) was signed out by \(row.providerName). Your browser opens \(row.providerName)'s sign-in page; come back here when you're done. Nimbus never sees your password.")
            actions {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open \(row.providerName) Sign-In") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        case .preparing, .waitingForBrowser:
            ProgressView().controlSize(.small)
            message(flow?.phase == .waitingForBrowser
                    ? "Finish signing in in your browser…"
                    : "Getting ready…")
            actions {
                Button("Cancel") { flow?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        case .finished:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
                .font(DesignSystem.Typography.headline)
            message("\(row.name) is ready again.")
            actions {
                Button("Done") { onFinished(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        case .needsSettings:
            message("\(row.name) needs more than a sign-in to reconnect. Open it and choose Edit to update its settings.")
            actions {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open \(row.name)") { onOpenCloud(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let reason):
            message("Signing in didn't finish.")
            Text(verbatim: reason)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            actions {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func start() {
        guard let flow else { return }
        Task { await flow.signIn() }
    }

    private func message(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DesignSystem.Spacing.s) { content() }
            .padding(.top, DesignSystem.Spacing.s)
    }
}

#if DEBUG
#Preview("Sign in again") {
    ReconnectSheet(row: HomePreviewData.work, onFinished: {}, onOpenCloud: {})
        .environment(RcloneDaemon())
}
#endif
