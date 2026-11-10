import SwiftUI
import RcloneKit

/// The window's landing screen: one storage bar for every cloud, one plain
/// sentence per cloud, and at most one problem with the button that fixes
/// it. Everything it says comes from `CloudSummaryBuilder`.
struct HomeView: View {
    let remotes: [Remote]
    /// A cloud the menu bar asked to sign in again; consumed on arrival.
    @Binding var pendingSignIn: String?
    let onOpenCloud: (String) -> Void
    let onCopyBetweenClouds: () -> Void

    @Environment(RemoteStatusService.self) private var statusService
    @Environment(TransferStore.self) private var transferStore
    @Environment(ProviderDirectory.self) private var providers
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @Environment(MountConfigStore.self) private var mountConfigs
    @Environment(AppRouter.self) private var router
    @Environment(BackupStore.self) private var backupStore
    @Environment(BackupRunner.self) private var backupRunner
    @Environment(BackupScheduler.self) private var backupScheduler

    @State private var reconnecting: CloudSummary.Row?
    @State private var finderError: NimbusError?

    private var summary: CloudSummary {
        CloudSummaryBuilder.live(remotes: remotes, status: statusService, transfers: transferStore,
                                 providers: providers, settings: settings, daemon: daemon,
                                 backups: backupStore, runner: backupRunner, scheduler: backupScheduler)
    }

    var body: some View {
        HomeContent(
            summary: summary,
            activity: ActivityLine.lines(from: transferStore.completedTransfers),
            providerCount: Set(providers.descriptions.values).count,
            actions: HomeActions(
                openCloud: onOpenCloud,
                openActivity: { route in
                    if case .cloud(let name) = route { onOpenCloud(name) } else { router.pending = route }
                },
                fix: fix,
                act: act(on:),
                dismiss: { settings.dismissedSuggestions.insert($0.id) },
                showInFinder: { name in Task { await showInFinder(name) } },
                openInFinder: { name in Task { await FinderIntegration.open(remote: name, bridge: fileProviderBridge) } },
                signIn: { reconnecting = $0 },
                copyBetweenClouds: onCopyBetweenClouds,
                addCloud: { router.pending = .addCloud },
                restartEngine: restartEngine
            )
        )
        .navigationTitle("Home")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Between Clouds…", action: onCopyBetweenClouds)
                    .disabled(remotes.count < 1)
                Button {
                    router.pending = .addCloud
                } label: {
                    Label("Add Cloud", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                // Not prominent: Home's one filled button is in its hero
                // or, when something is wrong, on the banner.
                .disabled(daemon.status != .connected)
            }
        }
        .onChange(of: pendingSignIn, initial: true) { _, name in
            guard let name else { return }
            pendingSignIn = nil
            reconnecting = summary.rows.first { $0.name == name }
        }
        .sheet(item: $reconnecting) { row in
            ReconnectSheet(
                row: row,
                onFinished: { Task { await statusService.probe(row.name) } },
                onOpenCloud: { onOpenCloud(row.name) }
            )
        }
        .alert(
            "Couldn't update Finder",
            isPresented: Binding(get: { finderError != nil }, set: { if !$0 { finderError = nil } }),
            presenting: finderError
        ) { _ in
            Button("OK", role: .cancel) { finderError = nil }
        } message: { error in
            Text(verbatim: error.message)
        }
    }

    // MARK: - Actions

    private func fix(_ row: CloudSummary.Row) {
        switch row.health {
        case .needsSignIn: reconnecting = row
        case .failing: onOpenCloud(row.name)
        default: Task { await statusService.probe(row.name) }
        }
    }

    private func act(on suggestion: CloudSummary.Suggestion) {
        switch suggestion {
        case .nearlyFull(let row): onOpenCloud(row.name)
        case .notInFinder(let row): Task { await showInFinder(row.name) }
        case .backup(let note): router.pending = .backups(note.jobID)
        }
    }

    private func showInFinder(_ name: String) async {
        do {
            try await FinderIntegration.show(remote: name, settings: settings, bridge: fileProviderBridge)
            FinderIntegration.ensureConfig(remote: name, store: mountConfigs, settings: settings)
        } catch {
            finderError = NimbusError.classify(error)
        }
    }

    private func restartEngine() {
        Task {
            await daemon.retry(
                binaryPath: settings.rcloneBinaryPath,
                bandwidthLimit: settings.bandwidthLimit,
                concurrentTransfers: settings.concurrentTransfers
            )
        }
    }
}
