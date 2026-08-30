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
    /// Title and message travel together, decided once at the point
    /// something fails, so an alert can never present a title that
    /// contradicts its own body — e.g. "Couldn't add remote" over a message
    /// that says the add can still proceed. Same principle as `trimmedName`
    /// being the one place "trimmed" is defined (C6 round 2).
    private struct SheetAlert: Equatable {
        let title: LocalizedStringKey
        let message: String
    }

    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var flow: RemoteSetupFlow?
    @State private var existingNames: Set<String> = []
    @State private var alert: SheetAlert?
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
            alert?.title ?? "Couldn't add remote",
            isPresented: Binding(
                get: { alert != nil },
                set: { if !$0 { alert = nil } }
            ),
            presenting: alert
        ) { _ in
            Button("OK", role: .cancel) { alert = nil }
        } message: { current in
            Text(verbatim: current.message)
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
                    answers: flow.answers,
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
        // oauthWaiting only means anything while parked in `.signingIn` (it
        // gates whether OAuthStep shows the "Sign In" CTA or the
        // waiting/Cancel state). The instant the walk LEAVES `.signingIn` —
        // whether forward on success, or via a re-walk that lands back on
        // `.signingIn` a SECOND time (an Exclusive answer change, or
        // toggling "Show all options"/"Edit advanced config") — reset it.
        // Without this, a second arrival at `.signingIn` inherits `true`
        // from the earlier attempt: OAuthStep renders the waiting spinner
        // with no Sign In button and no signIn() call in flight, which is a
        // permanent dead end (C1).
        .onChange(of: flow.phase) { _, newPhase in
            if case .signingIn = newPhase { } else { oauthWaiting = false }
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
        existingNames.contains(trimmedName(flow))
    }

    /// The single definition of what "trimmed" means for a remote name, so
    /// the live collision check and the value actually committed to
    /// `flow.name` before `begin()` can never disagree (C5).
    private func trimmedName(_ flow: RemoteSetupFlow) -> String {
        flow.name.trimmingCharacters(in: .whitespaces)
    }

    /// `.finished` is the only boundary where submitting actually creates
    /// the remote; `.oauth` walks to a browser sign-in and `.advancedGate`
    /// just advances the walk, so the button must not claim "Add Remote"
    /// for either (C4).
    private func pageButtonLabel(_ page: ConfigPage) -> LocalizedStringKey {
        if case .finished = page.boundary { return "Add Remote" }
        return "Continue"
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
                    Button("Continue") {
                        // Commit the trimmed value into the flow before
                        // begin() sends it to rclone — the single point
                        // where the name is finalized, so the collision
                        // check (which already trims) and the name rclone
                        // actually writes can never disagree (C5).
                        flow.name = trimmedName(flow)
                        Task { await flow.begin() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isNameValid(flow))
                } else if case .page(let page) = flow.phase {
                    // "Add Remote" is only true on a `.finished` boundary —
                    // an `.oauth` boundary walks to a browser sign-in, an
                    // `.advancedGate` boundary just advances the walk;
                    // neither creates anything yet (C4).
                    Button(pageButtonLabel(page)) { Task { await flow.submitPage() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            case .signingIn:
                // No Back here: RemoteSetupFlow has no page-back transition
                // to begin with — even when a `.page` (one whose boundary is
                // `.oauth`, i.e. exactly the page where the user just typed
                // client_id/client_secret) preceded this `.signingIn`, there
                // is no state to return TO. Cancel (which discards the flow
                // and returns to the picker) is the only way out (C3).
                Button("Cancel") {
                    Task { await flow.cancel(); self.flow = nil }
                }
                .keyboardShortcut(.cancelAction)
            case .creating:
                // Not a brief flicker: submitPage() deletes the stub and
                // re-walks the whole machine, up to 200 round trips against
                // the daemon. With no Cancel here, a stalled or wedged
                // daemon leaves force-quitting Nimbus as the only way out.
                // flow.cancel() is safe: performCancel() guards on
                // `phase != .finished`, and cancel() aborts the in-flight
                // walk rather than queuing behind it (C2).
                Button("Cancel") {
                    Task { await flow.cancel(); self.flow = nil }
                }
                .keyboardShortcut(.cancelAction)
            case .finished:
                // Genuinely momentary and self-dismissing — no buttons.
                EmptyView()
            }
        } else {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func isNameValid(_ flow: RemoteSetupFlow) -> Bool {
        let trimmed = trimmedName(flow)
        return !trimmed.isEmpty && !existingNames.contains(trimmed)
    }

    // MARK: - Loading

    private func loadProviders() async {
        do {
            providers = try await client.getProviders()
        } catch {
            // Fatal to this sheet: with no providers, there is nothing to
            // pick, so "Couldn't add remote" is an accurate title.
            alert = SheetAlert(
                title: "Couldn't add remote",
                message: NimbusError.classify(error).message
            )
            loadingProviders = false
            return
        }
        do {
            existingNames = Set(try await client.listRemotes())
        } catch {
            // Non-fatal: providers loaded fine, so the picker is still
            // fully usable — proceeding silently here would leave
            // duplicate-name detection permanently and invisibly off for
            // the rest of the session. Title and message are set together
            // here so they can't contradict each other the way a shared
            // "Couldn't add remote" title did over a body saying the add
            // could still proceed (C6 round 2).
            existingNames = []
            alert = SheetAlert(
                title: "Duplicate check unavailable",
                message: "Couldn't check for existing remote names, so a duplicate name may not be caught until rclone rejects it. You can still continue."
            )
        }
        loadingProviders = false
    }
}
