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
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderBridge.self) private var fileProviderBridge
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
    /// Finder integration failures for the remote just created. Non-empty
    /// keeps the sheet open on `.finished` so the user can retry or close
    /// instead of silently losing the "add to Finder" step.
    @State private var finderFailures: [RemoteIntegrationFailure] = []
    @State private var integrationStarted = false
    @State private var showImport = false
    @Environment(\.stratosphere) private var palette

    var body: some View {
        SheetChrome(
            title: "Add Cloud",
            // No subtitle: the identity header (badge + service name) carries
            // the selected provider once one is chosen; the picker needs none.
            subtitle: nil,
            body: { content },
            actions: { actions }
        )
        .frame(width: 600, height: 600)
        .task { await loadProviders() }
        .sheet(isPresented: $showImport) {
            // Import can't report cancel vs. success, so the Add sheet stays
            // put: cancelling Import lands back on the picker, and a finished
            // import refreshes the cloud list behind it.
            ImportConfigSheet(onDismiss: onDismiss)
        }
        .alert(
            alert?.title ?? "Couldn't add cloud",
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            SetupSteps(titles: stepTitles, current: currentStep)
            stepContent
        }
    }

    /// Step three is a browser sign-in for OAuth services and a short form
    /// for everything else; before rclone has answered, the catalog decides.
    private var stepTitles: [String] {
        let isOAuth = flow.map { $0.isOAuthBackend ?? PickerCatalog.isOAuth($0.provider.prefix) } ?? true
        return ["Choose a service", "Name it", isOAuth ? "Sign in" : "Set up"]
    }

    private var currentStep: Int {
        guard let flow else { return 0 }
        if case .naming = flow.phase { return 1 }
        return 2
    }

    @ViewBuilder
    private var stepContent: some View {
        if loadingProviders {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let flow {
            flowContent(flow)
        } else {
            ProviderPicker(providers: providers, onPick: { provider in
                oauthWaiting = false
                finderFailures = []
                integrationStarted = false
                self.flow = RemoteSetupFlow(provider: provider, client: client)
            }, onImport: { showImport = true })
        }
    }

    @ViewBuilder
    private func flowContent(_ flow: RemoteSetupFlow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            identityHeader(flow.provider)

            switch flow.phase {
            case .naming:
                FormSection(title: "Cloud", footer: nameFooter(flow)) {
                    FormRow(label: "Name", help: "The name you'll see in Nimbus and in Finder.") {
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
            case .page(let page) where page.boundary == .afterSignIn:
                if let question = page.questions.first {
                    FollowUpQuestion(
                        providerPrefix: flow.provider.prefix,
                        question: question,
                        value: flow.answers[question.option.name] ?? question.option.defaultValue,
                        onChange: { value in Task { await flow.answerChanged(question, to: value) } }
                    )
                }
            case .page(let page):
                ConfigPageForm(
                    page: page,
                    // Not after sign-in: the toggle restarts the walk, and
                    // the walk can't restart once the remote holds a token.
                    showAllOptionsIsMeaningful: flow.isOAuthBackend == true
                        && page.boundary != .afterSignIn,
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
                if finderFailures.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .task { await finishRemoteCreation(flow) }
                } else {
                    FinderIntegrationWarning(failures: finderFailures) {
                        Task { await retryFinderIntegration() }
                    }
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
                Text(verbatim: PickerCatalog.title(forPrefix: provider.prefix) ?? provider.description)
                    .font(DesignSystem.Stratosphere.Typography.label)
                    .foregroundStyle(palette.textPrimary.color)
                Text(verbatim: provider.name)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
    }

    private func nameFooter(_ flow: RemoteSetupFlow) -> LocalizedStringKey? {
        nameCollides(flow) ? "You already have a cloud with that name." : nil
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
        if case .finished = page.boundary { return "Add Cloud" }
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
                .buttonStyle(.glassCapsule)
                Button("Cancel") {
                    Task { await flow.cancel(); dismiss() }
                }
                .buttonStyle(.glassCapsule)
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
                    .buttonStyle(.primaryPill(.small))
                    .disabled(!isNameValid(flow))
                } else if case .page(let page) = flow.phase {
                    // "Add Remote" is only true on a `.finished` boundary —
                    // an `.oauth` boundary walks to a browser sign-in, an
                    // `.advancedGate` boundary just advances the walk;
                    // neither creates anything yet (C4).
                    Button(pageButtonLabel(page)) { Task { await flow.submitPage() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.primaryPill(.small))
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
                .buttonStyle(.glassCapsule)
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
                .buttonStyle(.glassCapsule)
                .keyboardShortcut(.cancelAction)
            case .finished:
                if finderFailures.isEmpty {
                    // Genuinely momentary and self-dismissing — no buttons.
                    EmptyView()
                } else {
                    Button("Close") { dismiss() }
                        .buttonStyle(.glassCapsule)
                        .keyboardShortcut(.cancelAction)
                }
            }
        } else {
            Button("Cancel") { dismiss() }
                .buttonStyle(.glassCapsule)
                .keyboardShortcut(.cancelAction)
        }
    }

    private func isNameValid(_ flow: RemoteSetupFlow) -> Bool {
        let trimmed = trimmedName(flow)
        return !trimmed.isEmpty && !existingNames.contains(trimmed)
    }

    // MARK: - Finder integration

    /// Runs once per created remote: refreshes the caller, applies the
    /// "add new remotes to Finder" default, and dismisses unless Finder
    /// integration failed, in which case the warning takes over the sheet.
    private func finishRemoteCreation(_ flow: RemoteSetupFlow) async {
        guard !integrationStarted else { return }
        integrationStarted = true
        onDismiss()
        let result = await NewRemoteIntegration(domainAdder: fileProviderBridge).integrate(
            names: [flow.name],
            addToFinder: settings.addNewRemotesToFinder,
            disabledDomainNames: settings.disabledFileProviderDomains
        )
        settings.disabledFileProviderDomains = result.disabledDomainNames
        finderFailures = result.failures
        if finderFailures.isEmpty {
            dismiss()
        }
    }

    private func retryFinderIntegration() async {
        let failedNames = finderFailures.map(\.remoteName)
        finderFailures = await NewRemoteIntegration(domainAdder: fileProviderBridge)
            .integrate(names: failedNames, addToFinder: true)
        if finderFailures.isEmpty {
            dismiss()
        }
    }

    // MARK: - Loading

    private func loadProviders() async {
        do {
            providers = try await client.getProviders()
        } catch {
            // Fatal to this sheet: with no providers, there is nothing to
            // pick, so "Couldn't add remote" is an accurate title.
            alert = SheetAlert(
                title: "Couldn't add cloud",
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
                message: "Couldn't check the names you already use, so a duplicate may only be caught when you finish. You can still continue."
            )
        }
        loadingProviders = false
    }
}
