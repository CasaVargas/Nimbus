import SwiftUI
import RcloneKit

/// Hosts the guided Add Remote flow: pick a provider, then drive
/// `RemoteSetupFlow` through rclone's interactive `config/create` state
/// machine until the remote exists.
///
/// `ProviderPicker` is shown first and needs no flow. `RemoteSetupFlow` is
/// only constructed once a provider is chosen, so `.naming` is the flow's
/// first phase, not this sheet's first screen — Back from `.naming`
/// discards the flow and returns to the picker.
struct AddRemoteSheet: View {
    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var flow: RemoteSetupFlow?
    @State private var existingNames: Set<String> = []
    @State private var error: NimbusError?
    @State private var loadingProviders = true
    /// Whether the current `.signingIn` sub-state has actually started
    /// rclone's blocking sign-in call (vs. showing the "Sign In" CTA).
    /// Reset every time a fresh flow is created so a later attempt never
    /// inherits a previous attempt's waiting state.
    @State private var oauthWaiting = false

    var body: some View {
        SheetChrome(
            title: "Add Remote",
            // No subtitle: the identity header (badge + service name) carries
            // the selected provider once one is chosen; the picker needs none.
            subtitle: nil,
            body: { content },
            actions: { actions }
        )
        .frame(width: 560, height: 560)
        .task { await loadProviders() }
        .alert(
            "Couldn't add remote",
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

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if loadingProviders {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let flow {
            flowContent(flow)
        } else {
            ProviderPicker(providers: providers) { provider in
                oauthWaiting = false
                self.flow = RemoteSetupFlow(provider: provider, client: client)
            }
        }
    }

    @ViewBuilder
    private func flowContent(_ flow: RemoteSetupFlow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            identityHeader(flow.provider)

            switch flow.phase {
            case .naming:
                FormSection(title: "Remote", footer: nameFooter(flow)) {
                    FormRow(label: "Name", help: "Used to reference this remote in the Browser.") {
                        TextField("e.g. gdrive", text: Binding(
                            get: { flow.name },
                            set: { flow.name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    }
                }
            case .loading, .creating:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .page(let page):
                ConfigPageForm(
                    page: page,
                    showAllOptionsIsMeaningful: flow.isOAuthBackend == true,
                    answers: Binding(get: { flow.answers }, set: { flow.answers = $0 }),
                    showAllOptions: Binding(
                        get: { flow.showAllOptions },
                        set: { flow.showAllOptions = $0; Task { await flow.rewalk() } }
                    ),
                    includeAdvanced: Binding(
                        get: { flow.includeAdvanced },
                        set: { flow.includeAdvanced = $0 }
                    ),
                    onAnswerChanged: { question, value in
                        Task { await flow.answerChanged(question, to: value) }
                    }
                )
            case .signingIn:
                OAuthStep(
                    provider: flow.provider,
                    isWaiting: oauthWaiting,
                    onSignIn: {
                        oauthWaiting = true
                        Task { await flow.signIn() }
                    },
                    onCancel: { Task { await flow.cancel(); self.flow = nil } }
                )
            case .finished:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .task {
                        onDismiss()
                        dismiss()
                    }
            case .failed(let message):
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Setup Failed",
                    messageVerbatim: message,
                    action: .init(label: "Start Over", perform: { self.flow = nil })
                )
            }
        }
    }

    private func identityHeader(_ provider: Provider) -> some View {
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
    }

    private func nameFooter(_ flow: RemoteSetupFlow) -> LocalizedStringKey? {
        nameCollides(flow) ? "A remote with that name already exists." : nil
    }

    private func nameCollides(_ flow: RemoteSetupFlow) -> Bool {
        existingNames.contains(flow.name.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if let flow {
            switch flow.phase {
            case .naming, .loading, .page, .failed:
                Button("Back") {
                    Task { await flow.cancel(); self.flow = nil }
                }
                Button("Cancel") {
                    Task { await flow.cancel(); dismiss() }
                }
                .keyboardShortcut(.cancelAction)

                if case .naming = flow.phase {
                    Button("Continue") { Task { await flow.begin() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!isNameValid(flow))
                } else if case .page = flow.phase {
                    Button("Add Remote") { Task { await flow.submitPage() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            case .signingIn:
                // No Back here: the OAuth step is reached directly from
                // naming/loading with no intermediate page to return to, and
                // Cancel (which fully discards the flow) covers backing out.
                Button("Cancel") {
                    Task { await flow.cancel(); self.flow = nil }
                }
                .keyboardShortcut(.cancelAction)
            case .creating, .finished:
                // Both are transient, non-interactive states — .creating is
                // mid-write to rclone.conf, .finished is asynchronously
                // dismissing the sheet. Showing live destructive buttons on
                // either is wrong even though cancel() itself now no-ops
                // once .finished.
                EmptyView()
            }
        } else {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func isNameValid(_ flow: RemoteSetupFlow) -> Bool {
        let trimmed = flow.name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !existingNames.contains(trimmed)
    }

    // MARK: - Loading

    private func loadProviders() async {
        do {
            providers = try await client.getProviders()
            existingNames = Set(try await client.listRemotes())
        } catch {
            self.error = NimbusError.classify(error)
        }
        loadingProviders = false
    }
}
