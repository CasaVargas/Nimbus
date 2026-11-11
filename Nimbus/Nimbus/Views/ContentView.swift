import SwiftUI
import RcloneKit
import os

struct ContentView: View {
    @State private var selection: SidebarSelection? = .home
    @State private var browseTarget: BrowseTarget?
    @State private var pendingSidebarCopy: CopyRequest?
    /// A Home sign-in the menu bar asked for, handed to HomeView.
    @State private var pendingSignIn: String?
    /// A volume tab the menu bar asked for ("Show Transfers").
    @State private var requestedVolumeTab: VolumeTab?
    /// Source remote to preselect when Copy & Sync opens from a volume.
    @State private var copySyncSource: String?
    @State private var copySyncSourcePath: String?
    @State private var pendingBackupDraft: BackupJob?
    /// A backup a notification asked to open on.
    @State private var backupFocus: UUID?
    /// Toolbar search text. Any non-blank text puts search results in the
    /// detail pane; clearing it brings back the previous screen.
    @State private var searchText = ""
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var transferStore
    @Environment(CloudMonitor.self) private var monitor
    @Environment(AppRouter.self) private var router

    private var remotes: [Remote] { monitor.remotes }

    /// An alias takes the colour of the backend it points at, the same way
    /// it takes that backend's logo.
    private var cloudColors: [String: DesignSystem.Stratosphere.CloudColor] {
        DesignSystem.Stratosphere.CloudColors.assign(remotes.map {
            (name: $0.name, provider: CloudNaming.resolvedType(of: $0, in: remotes))
        })
    }

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(
                    selection: $selection,
                    onBookmarkSelected: { remote, path in
                        selection = .remote(remote)
                        browseTarget = BrowseTarget(remote: remote, path: path)
                    },
                    onBookmarkDrop: { bundles, bookmark in
                        handleBookmarkDrop(refs: bundles.flatMap(\.refs), bookmark: bookmark)
                    }
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            } detail: {
                detailView
            }
            .navigationSplitViewStyle(.balanced)
            .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search all clouds"))
            .frame(minWidth: 800, minHeight: 600)
            // One backdrop for the whole window, behind the sidebar and the
            // toolbar as well as the detail.
            .containerBackground(for: .window) { StratosphereBackdrop() }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .environment(\.cloudColors, cloudColors)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .focusedSceneValue(\.sidebarSelection, $selection)
            .onChange(of: monitor.remotes.map(\.name)) { _, names in
                // Only after a real load: a not-yet-loaded empty list must
                // never bounce the user off the cloud they had open.
                guard monitor.hasLoaded else { return }
                selection = nextSelection(current: selection, remotes: names)
            }
            .onChange(of: router.pending, initial: true) { handleRoute() }
            .onAppear { router.isMainWindowOpen = true }
            .onDisappear { router.isMainWindowOpen = false }
            .environment(\.openBrowser, OpenBrowserAction { remote in
                selection = .remote(remote)
                browseTarget = BrowseTarget(remote: remote, path: "")
            })
            .sheet(item: $pendingSidebarCopy) { _ in
                ConfirmCopySheet(request: $pendingSidebarCopy) { req in
                    Task {
                        let coord = DragDropCoordinator(
                            transferStore: transferStore,
                            rclone: RcloneClientAdapter(client: daemon.client)
                        )
                        do {
                            try await coord.apply(
                                .crossRemote(items: req.items, sourceRemote: req.sourceRemote, target: req.target),
                                conflictPolicy: req.conflictPolicy
                            )
                        } catch {
                            Logger(subsystem: "app.casavargas.nimbus", category: "sidebar")
                                .error("Bookmark cross-remote copy failed: \(String(describing: error))")
                        }
                    }
                }
            }
        }
    }

    /// Acts on menu bar requests addressed to the window. Add Cloud is left
    /// for the sidebar section, which owns that sheet.
    private func handleRoute() {
        guard let route = router.take(where: { $0 != .addCloud }) else { return }
        switch route {
        case .home:
            selection = .home
        case .cloud(let name):
            selection = .remote(name)
        case .browse(let name, let path):
            requestedVolumeTab = .files
            selection = .remote(name)
            browseTarget = BrowseTarget(remote: name, path: path)
        case .transfers(let name):
            requestedVolumeTab = .transfers
            selection = .remote(name)
        case .signIn(let name):
            selection = .home
            pendingSignIn = name
        case .backups(let id):
            backupFocus = id
            selection = .backups
        case .addCloud:
            break
        }
    }

    private func handleBookmarkDrop(refs: [NimbusFileRef], bookmark: FolderBookmark) {
        let coord = DragDropCoordinator(
            transferStore: transferStore,
            rclone: RcloneClientAdapter(client: daemon.client)
        )
        let target = DropIntent.DropTarget(remote: bookmark.remoteName, path: bookmark.path)
        do {
            let intent = try coord.resolve(drop: refs, onto: target)
            if case .crossRemote(let items, let sourceRemote, let resolvedTarget) = intent {
                pendingSidebarCopy = CopyRequest(
                    sourceRemote: sourceRemote,
                    target: resolvedTarget,
                    items: items,
                    conflictPolicy: settings.defaultConflictPolicy
                )
            }
            // Within-remote / toFinder bookmark drops are no-ops in Phase 1.
        } catch {
            Logger(subsystem: "app.casavargas.nimbus", category: "sidebar")
                .warning("Bookmark drop resolve error: \(String(describing: error))")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if !SearchViewModel.normalized(searchText).isEmpty {
            SearchResultsView(query: searchText, remotes: remotes) { remote, folder in
                requestedVolumeTab = .files
                selection = .remote(remote)
                browseTarget = BrowseTarget(remote: remote, path: folder)
                searchText = ""
            }
        } else {
            screenView
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch selection {
        case .home, nil:
            HomeView(
                remotes: remotes,
                pendingSignIn: $pendingSignIn,
                onOpenCloud: { selection = .remote($0) },
                onCopyBetweenClouds: {
                    copySyncSource = nil
                    copySyncSourcePath = nil
                    selection = .copySync
                }
            )
        case .remote(let name):
            if let remote = remotes.first(where: { $0.name == name }) {
                VolumeView(
                    remote: remote,
                    allRemotes: remotes,
                    requestedTab: $requestedVolumeTab,
                    browseTarget: browseTarget,
                    onSync: { source, path in
                        copySyncSource = source
                        copySyncSourcePath = path
                        selection = .copySync
                    }
                )
                .id(name)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .copySync:
            CopySyncView(
                initialSource: copySyncSource,
                initialSourcePath: copySyncSourcePath,
                onSaveAsBackup: { draft in
                    pendingBackupDraft = draft
                    selection = .backups
                }
            )
        case .backups:
            BackupsView(
                pendingDraft: $pendingBackupDraft,
                focusedJob: $backupFocus,
                onShowHistory: { cloud in
                    requestedVolumeTab = .transfers
                    selection = .remote(cloud)
                }
            )
        }
    }
}

struct OpenBrowserAction {
    let action: (String) -> Void
    func callAsFunction(_ remote: String) { action(remote) }
}

extension EnvironmentValues {
    @Entry var openBrowser = OpenBrowserAction { _ in }
}
