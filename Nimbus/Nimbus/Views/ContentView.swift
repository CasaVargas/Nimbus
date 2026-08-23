import SwiftUI
import os

struct ContentView: View {
    @State private var selection: SidebarSelection?
    @State private var browseTarget: BrowseTarget?
    @State private var pendingSidebarCopy: CopyRequest?
    /// Last remote list reported by the sidebar — distinguishes "no remotes
    /// configured yet" from "remotes exist, none selected" in the detail pane.
    @State private var remoteNames: [String] = []
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var transferStore

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(
                    selection: $selection,
                    onRemotesLoaded: { names in
                        remoteNames = names
                        selection = nextSelection(current: selection, remotes: names)
                    },
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
            .frame(minWidth: 800, minHeight: 600)
            .background(DesignSystem.Color.semantic.surface)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .focusedSceneValue(\.sidebarSelection, $selection)
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
                    items: items
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
        switch selection {
        case .remote(let name):
            BrowserView(
                remoteName: name,
                initialPath: browseTarget?.remote == name ? (browseTarget?.path ?? "") : "",
                browseTarget: browseTarget
            )
            .id(name)
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case nil:
            noSelectionView
        }
    }

    /// The nil-selection pane doubles as the daemon status surface: it is
    /// where a user lands on first launch and after failures, so it must
    /// offer recovery (Retry) rather than just describing the problem.
    @ViewBuilder
    private var noSelectionView: some View {
        switch daemon.status {
        case .idle, .starting:
            VStack(spacing: DesignSystem.Spacing.m) {
                ProgressView()
                    .controlSize(.large)
                Text("Connecting to rclone…")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "rclone Isn't Running",
                messageVerbatim: message,
                action: .init(label: "Retry", perform: {
                    Task { await daemon.retry(binaryPath: settings.rcloneBinaryPath) }
                })
            )
        case .connected:
            if remoteNames.isEmpty {
                EmptyState(
                    icon: "cloud.slash",
                    title: "No Remotes Yet",
                    message: "Add your first remote with the + button in the sidebar.",
                    action: nil
                )
            } else {
                EmptyState(
                    icon: "cloud.slash",
                    title: "No Remote Selected",
                    message: "Select a remote in the sidebar to browse it.",
                    action: nil
                )
            }
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
