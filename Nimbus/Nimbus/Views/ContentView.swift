import SwiftUI
import RcloneKit
import os

struct ContentView: View {
    @State private var selection: SidebarSelection? = .home
    @State private var browseTarget: BrowseTarget?
    @State private var pendingSidebarCopy: CopyRequest?
    /// Last remote list reported by the sidebar — distinguishes "no remotes
    /// configured yet" from "remotes exist, none selected" in the detail pane,
    /// and supplies the `Remote` the volume pane renders.
    @State private var remotes: [Remote] = []
    /// Source remote to preselect when Copy & Sync opens from a volume.
    @State private var copySyncSource: String?
    @State private var copySyncSourcePath: String?
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
                    onRemotesLoaded: { list in
                        remotes = list
                        selection = nextSelection(current: selection, remotes: list.map(\.name))
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
        switch selection {
        case .home, nil:
            HomeView(
                remotes: remotes,
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
            CopySyncView(initialSource: copySyncSource, initialSourcePath: copySyncSourcePath)
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
