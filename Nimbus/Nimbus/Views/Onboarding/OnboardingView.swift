import SwiftUI
import RcloneKit

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var mountStore
    @Environment(MountManager.self) private var mountManager

    @State private var remotes: [String] = []
    @State private var showAddRemote = false
    @State private var showAddMount = false
    @State private var mountsViewModel: MountsViewModel?

    private var hasRemotes: Bool { !remotes.isEmpty }
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
            Image(systemName: "cloud")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
            Text("Welcome to Nimbus")
                .font(DesignSystem.Typography.largeTitle.bold())
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            Text("Your cloud storage, managed natively.")
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
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
        case .connected: return "Rclone is ready."
        case .error(let message): return LocalizedStringKey(message)
        }
    }

    private var daemonRetryAction: OnboardingCard.ActionConfig? {
        guard case .error = daemon.status else { return nil }
        return .init(label: "Retry", perform: {
            Task { await daemon.retry(binaryPath: settings.rcloneBinaryPath) }
        })
    }

    private var addRemoteCard: some View {
        OnboardingCard(
            state: hasRemotes ? .complete : .actionRequired,
            icon: "cloud",
            title: "Add a Remote",
            message: hasRemotes
                ? LocalizedStringKey("Connected to \(remotes.first ?? "your provider").")
                : LocalizedStringKey("Connect a cloud provider to get started."),
            primaryAction: hasRemotes ? nil : .init(label: "Add Remote", perform: { showAddRemote = true }),
            secondaryAction: hasRemotes ? .init(label: "Mount it for Finder →", perform: { showAddMount = true }) : nil
        )
    }

    private var addMountCard: some View {
        OnboardingCard(
            state: hasMounts ? .complete : .actionRequired,
            icon: "externaldrive",
            title: "Mount Your Remote",
            message: hasMounts
                ? (firstMountPath.isEmpty
                    ? LocalizedStringKey("Remote mounted successfully.")
                    : LocalizedStringKey("Mounted at \(firstMountPath)."))
                : LocalizedStringKey("Mount the remote to access it in Finder."),
            primaryAction: hasMounts ? nil : .init(label: "Add Mount", perform: { showAddMount = true }),
            secondaryAction: hasMounts ? .init(label: "Browse it →", perform: { finish() }) : nil
        )
    }

    private var doneCard: some View {
        OnboardingCard(
            state: .complete,
            icon: "checkmark.seal.fill",
            title: "You're All Set",
            message: "Nimbus is ready to manage your cloud storage.",
            primaryAction: .init(label: "Done", perform: { finish() }),
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
        // If a new mount was added that isn't yet mounted, mount it now.
        for config in mountStore.configs where !mountManager.mountedIDs.contains(config.id) {
            try? await mountManager.mountConfig(config)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings())
        .environment(RcloneDaemon())
        .environment(MountConfigStore())
        .environment(MountManager())
        .frame(width: 700, height: 800)
}
