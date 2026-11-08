import SwiftUI
import RcloneKit

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var mountStore
    @Environment(MountManager.self) private var mountManager
    @Environment(FileProviderBridge.self) private var fileProviderBridge

    @State private var remotes: [String] = []
    @State private var showAddRemote = false
    @State private var showAddMount = false
    @State private var mountsViewModel: MountsViewModel?

    private var hasRemotes: Bool { !remotes.isEmpty }
    // Phase 2b: hasMounts reflects config presence, not actual mount state.
    // Acceptable for the wedge flow (mount usually <2s); Phase 3 should
    // gate this on mountManager.mountedIDs for accuracy.
    private var hasMounts: Bool { !mountStore.configs.isEmpty }
    private var canShowMountCard: Bool { hasRemotes }
    private var canShowDoneCard: Bool { hasRemotes && hasMounts }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.l) {
                hero
                cardStack
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.xxl)
            .animation(DesignSystem.Motion.smooth, value: daemon.status)
            .animation(DesignSystem.Motion.smooth, value: hasRemotes)
            .animation(DesignSystem.Motion.smooth, value: hasMounts)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Color.semantic.surface)
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(client: daemon.client, onDismiss: {
                Task { await refreshRemotes() }
            })
        }
        .sheet(isPresented: $showAddMount) {
            if let mountsViewModel {
                AddMountSheet(viewModel: mountsViewModel)
                    .task {
                        await mountsViewModel.loadRemotes()
                    }
            }
        }
        .task(id: daemon.status) {
            if daemon.status == .connected {
                await refreshRemotes()
            }
        }
        // Onboarding only adds (never edits) configs, so .count is sufficient
        // to detect new additions. Counting avoids requiring MountConfig: Equatable.
        .onChange(of: mountStore.configs.count) { _, _ in
            Task { await attemptAutoMount() }
        }
        .onAppear {
            if mountsViewModel == nil {
                mountsViewModel = MountsViewModel(client: daemon.client)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("Welcome to Nimbus")
                .font(DesignSystem.Typography.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            Text("Your cloud storage, managed natively.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Label("Private by design · Powered by macOS File Provider", systemImage: "checkmark.shield")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
        }
        .padding(.bottom, DesignSystem.Spacing.l)
    }

    @ViewBuilder
    private var cardStack: some View {
        daemonCard

        if daemon.status == .connected {
            addRemoteCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if canShowMountCard {
            addMountCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if canShowDoneCard {
            doneCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Cards

    private var daemonCard: some View {
        OnboardingCard(
            state: daemonCardState,
            icon: "bolt",
            title: "Rclone Daemon",
            message: daemonCardMessage,
            primaryAction: daemonRetryAction,
            secondaryAction: nil
        )
    }

    private var daemonCardState: OnboardingCardState {
        switch daemon.status {
        case .idle, .starting: return .inProgress
        case .connected: return .complete
        case .error: return .actionRequired
        }
    }

    private var daemonCardMessage: LocalizedStringKey {
        switch daemon.status {
        case .idle: return "Waiting to start…"
        case .starting: return "Connecting to rclone…"
        case .connected: return "Secure cloud connection is ready."
        case .error(let message): return LocalizedStringKey(message)
        }
    }

    private var daemonRetryAction: OnboardingCard.ActionConfig? {
        guard case .error = daemon.status else { return nil }
        return .init(label: "Retry", perform: {
            Task {
                await daemon.retry(
                    binaryPath: settings.rcloneBinaryPath,
                    bandwidthLimit: settings.bandwidthLimit,
                    concurrentTransfers: settings.concurrentTransfers
                )
            }
        })
    }

    private var addRemoteCard: some View {
        OnboardingCard(
            state: hasRemotes ? .complete : .actionRequired,
            icon: "cloud",
            title: "Add a Remote",
            message: hasRemotes
                ? LocalizedStringKey("Connected to \(remotes.first ?? "your provider").")
                : LocalizedStringKey("Choose from Google Drive, OneDrive, S3, Dropbox, and more."),
            primaryAction: hasRemotes ? nil : .init(label: "Add Remote", perform: { showAddRemote = true }),
            secondaryAction: hasRemotes ? .init(label: "Show it in Finder", perform: { showAddMount = true }) : nil
        )
    }

    private var addMountCard: some View {
        OnboardingCard(
            state: hasMounts ? .complete : .actionRequired,
            icon: "macwindow.badge.plus",
            title: "Add It to Finder",
            message: hasMounts
                ? (firstMountPath.isEmpty
                    ? LocalizedStringKey("Your remote is available as a Finder location.")
                    : LocalizedStringKey("Available at \(firstMountPath)."))
                : LocalizedStringKey("Browse cloud files beside iCloud Drive. macOS downloads them on demand."),
            primaryAction: hasMounts ? nil : .init(label: "Add to Finder", perform: { showAddMount = true }),
            secondaryAction: hasMounts ? .init(label: "Open Nimbus →", perform: { finish() }) : nil
        )
    }

    private var doneCard: some View {
        OnboardingCard(
            state: .complete,
            icon: "checkmark.seal.fill",
            title: "You're All Set",
            message: "Your cloud is connected and ready in Finder.",
            primaryAction: .init(label: "Start Browsing", perform: { finish() }),
            secondaryAction: nil
        )
    }

    // MARK: - Actions

    private var firstMountPath: String {
        mountStore.configs.first?.mountPoint ?? ""
    }

    private func finish() {
        settings.onboardingComplete = true
    }

    private func refreshRemotes() async {
        do {
            let names = try await daemon.client.listRemotes()
            remotes = names
        } catch {
            // Silent — daemon error state surfaces via daemon.status, not here.
        }
    }

    private func attemptAutoMount() async {
        // Bring up each newly-added config that isn't live yet. Mirrors
        // MountsView.toggle: NFS spins up an rclone serve + mount_nfs; File
        // Provider registers a Finder domain. Both backends must be handled —
        // AddMountSheet defaults to .fileProvider, and if this only mounted
        // .nfs the onboarding card would flip to "mounted" while nothing was
        // ever registered, so nothing appeared in Finder.
        for config in mountStore.configs {
            switch config.backend {
            case .nfs:
                // Filtering on inFlight as well closes the double-dispatch race
                // where two overlapping .onChange tasks both pass the mountedIDs
                // check before either reaches mountConfig's first suspension point.
                guard !mountManager.mountedIDs.contains(config.id),
                      !mountManager.inFlight.contains(config.id) else { continue }
                try? await mountManager.mountConfig(config)
            case .fileProvider:
                let name = config.remoteNameOnly
                guard !fileProviderBridge.activeDomains.contains(name) else { continue }
                try? await fileProviderBridge.addDomain(identifier: name, displayName: name)
                // The launch-time domain sync re-registers every remote it isn't
                // told to skip; clear any stale skip flag so it stays registered.
                settings.disabledFileProviderDomains.remove(name)
                await fileProviderBridge.refreshDomains()
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .environment(MountConfigStore())
        .environment(MountManager())
        .environment(FileProviderBridge())
        .frame(width: 700, height: 800)
}
