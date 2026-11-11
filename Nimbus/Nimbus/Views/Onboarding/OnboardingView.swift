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
    @State private var installer: RcloneInstaller
    @Environment(\.stratosphere) private var palette

    init(installer: RcloneInstaller = RcloneInstaller()) {
        _installer = State(initialValue: installer)
    }

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
            .animation(DesignSystem.Motion.smooth, value: installer.phase)
            .animation(DesignSystem.Motion.smooth, value: hasRemotes)
            .animation(DesignSystem.Motion.smooth, value: hasMounts)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { StratosphereBackdrop() }
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
            constellation
            Text("Every cloud, one window")
                .font(DesignSystem.Stratosphere.Typography.hero)
                .foregroundStyle(palette.textPrimary.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text("Browse, copy and back up across Google Drive, OneDrive, Dropbox and dozens more.")
                .font(DesignSystem.Stratosphere.Typography.lead)
                .foregroundStyle(palette.textSecondary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            HStack(spacing: DesignSystem.Spacing.s) {
                Chip(text: Text("Shows up in Finder"), systemImage: "folder")
                Chip(text: Text("Copies cloud to cloud"), systemImage: "arrow.left.arrow.right")
                Chip(text: Text("Backs up your folders"), systemImage: "checkmark.shield")
            }
            .padding(.top, DesignSystem.Spacing.xs)
            Label("Private by design · Powered by macOS File Provider", systemImage: "checkmark.shield")
                .font(DesignSystem.Stratosphere.Typography.detail)
                .foregroundStyle(palette.textTertiary.color)
        }
        .padding(.bottom, DesignSystem.Spacing.l)
    }

    /// The app icon in a halo with the services it reaches floating around
    /// it. Decoration only: the sentence below names the services.
    private var constellation: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [palette.actionTop.color.opacity(0.6), palette.actionTop.color.opacity(0)],
                    center: .center, startRadius: 40, endRadius: 110
                ))
                .frame(width: 220, height: 220)
            ForEach(Self.satellites, id: \.provider) { satellite in
                LogoTile(provider: satellite.provider, size: satellite.size)
                    .rotationEffect(.degrees(satellite.tilt))
                    .offset(x: satellite.x, y: satellite.y)
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .shadow(color: palette.actionGlow.color, radius: 22, y: 12)
        }
        .frame(width: 520, height: 220)
        .accessibilityHidden(true)
    }

    private struct Satellite {
        let provider: String
        let size: LogoTile.Size
        let x: CGFloat
        let y: CGFloat
        let tilt: Double
    }

    private static let satellites: [Satellite] = [
        .init(provider: "drive", size: .large, x: -170, y: -52, tilt: -10),
        .init(provider: "dropbox", size: .medium, x: -214, y: 38, tilt: 8),
        .init(provider: "box", size: .compact, x: -120, y: 82, tilt: -4),
        .init(provider: "onedrive", size: .large, x: 172, y: -60, tilt: 9),
        .init(provider: "b2", size: .medium, x: 208, y: 30, tilt: -8),
        .init(provider: "iclouddrive", size: .compact, x: 118, y: 84, tilt: 6),
    ]

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

    @ViewBuilder
    private var daemonCard: some View {
        if offersDownload {
            rcloneDownloadCard
        } else {
            OnboardingCard(
                state: daemonCardState,
                icon: "bolt",
                title: "Connection Engine",
                message: daemonCardMessage,
                primaryAction: daemonRetryAction,
                secondaryAction: nil
            )
        }
    }

    /// No rclone at the configured path, or a download is under way or just
    /// failed. Once installed the path is executable and the normal card
    /// returns to show the daemon starting.
    private var offersDownload: Bool {
        switch installer.phase {
        case .checking, .downloading, .verifying, .installing, .failed: return true
        case .idle, .installed, .upToDate:
            return !FileManager.default.isExecutableFile(atPath: settings.rcloneBinaryPath)
        }
    }

    private var rcloneDownloadCard: some View {
        OnboardingCard(
            state: installer.phase.isBusy ? .inProgress : .actionRequired,
            icon: "bolt",
            title: "Connection Engine",
            message: downloadMessage,
            primaryAction: installer.phase.isBusy ? nil : .init(
                label: installer.phase == .idle ? "Download rclone" : "Try Again",
                perform: { Task { await downloadRclone() } }
            ),
            secondaryAction: installer.phase.isBusy ? nil : .init(
                label: "Installed it with Homebrew? Check again",
                perform: { Task { await recheckRclone() } }
            )
        )
    }

    private var downloadMessage: LocalizedStringKey {
        switch installer.phase {
        case .idle, .installed, .upToDate:
            return "Nimbus uses rclone to reach your clouds, and this Mac doesn't have it yet. Nimbus can download the official build from rclone.org (about 30 MB) and check it against rclone's published checksums. Or run `brew install rclone`."
        case .checking: return "Checking rclone.org for the latest version…"
        case .downloading(let version): return "Downloading rclone \(version)…"
        case .verifying: return "Checking the download against rclone's published checksums…"
        case .installing: return "Installing rclone…"
        case .failed(let failure): return LocalizedStringKey(failure.message)
        }
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
        case .starting: return "Starting…"
        case .connected: return "Ready to connect to your clouds."
        case .error(let message): return LocalizedStringKey(message)
        }
    }

    private var daemonRetryAction: OnboardingCard.ActionConfig? {
        guard case .error = daemon.status else { return nil }
        return .init(label: "Retry", perform: {
            Task { await startDaemon() }
        })
    }

    private var addRemoteCard: some View {
        OnboardingCard(
            state: hasRemotes ? .complete : .actionRequired,
            icon: "cloud",
            title: "Add a Cloud",
            message: hasRemotes
                ? LocalizedStringKey("Connected to \(remotes.first ?? "your provider").")
                : LocalizedStringKey("Choose from Google Drive, OneDrive, S3, Dropbox, and more."),
            primaryAction: hasRemotes ? nil : .init(label: "Add Cloud", perform: { showAddRemote = true }),
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
                    ? LocalizedStringKey("Your cloud is available as a Finder location.")
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

    private func startDaemon() async {
        mountManager.rcloneBinaryPath = settings.rcloneBinaryPath
        await daemon.retry(
            binaryPath: settings.rcloneBinaryPath,
            bandwidthLimit: settings.bandwidthLimit,
            concurrentTransfers: settings.concurrentTransfers
        )
    }

    private func downloadRclone() async {
        guard let path = await installer.install() else { return }
        settings.rcloneBinaryPath = path
        await startDaemon()
    }

    /// Looks again in the usual places, e.g. after `brew install rclone`.
    private func recheckRclone() async {
        if let found = AppSettings.locateRclone() {
            settings.rcloneBinaryPath = found
            installer.reset()
        }
        await startDaemon()
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

#Preview("No rclone yet") {
    let defaults = UserDefaults(suiteName: "preview.onboarding.no-rclone")!
    defaults.set("/nonexistent/rclone", forKey: "rcloneBinaryPath")
    return OnboardingView()
        .environment(AppSettings(defaults: defaults))
        .environment(RcloneDaemon())
        .environment(MountConfigStore())
        .environment(MountManager())
        .environment(FileProviderBridge())
        .frame(width: 700, height: 800)
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
