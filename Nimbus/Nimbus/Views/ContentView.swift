import SwiftUI
import os

// Value type pushed onto the NavigationStack path when the user browses a remote.
struct BrowserDestination: Hashable {
    let remoteName: String
    var initialPath: String = ""
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .remotes
    @State private var navigationPath = NavigationPath()
    @State private var pendingSidebarCopy: CopyRequest?
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
                    onBookmarkSelected: { remote, path in
                        selection = .remotes
                        navigationPath.append(BrowserDestination(remoteName: remote, initialPath: path))
                    },
                    onBookmarkDrop: { bundles, bookmark in
                        let refs = bundles.flatMap(\.refs)
                        handleBookmarkDrop(refs: refs, bookmark: bookmark)
                    }
                )
                .frame(minWidth: 180)
            } detail: {
                NavigationStack(path: $navigationPath) {
                    detailView
                        .navigationDestination(for: BrowserDestination.self) { destination in
                            BrowserView(remoteName: destination.remoteName, initialPath: destination.initialPath)
                        }
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .environment(\.openBrowser, OpenBrowserAction { remote in
                navigationPath.append(BrowserDestination(remoteName: remote))
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
        case .remotes:
            RemotesView(onBrowse: { remote in
                navigationPath.append(BrowserDestination(remoteName: remote))
            })
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case .settings:
            SettingsView()
        case nil:
            Text("Select an item from the sidebar")
                .foregroundStyle(.secondary)
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
