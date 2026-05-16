import SwiftUI
import RcloneKit
import os

struct BrowserView: View {
    let remoteName: String
    var initialPath: String = ""
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(BookmarkStore.self) private var bookmarkStore
    @Environment(TransferStore.self) private var transferStore
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @State private var viewModel: BrowserViewModel?
    @State private var pendingCopy: CopyRequest?
    @State private var quickLookHost = QuickLookHost()

    var body: some View {
        Group {
            if let viewModel {
                VStack(spacing: 0) {
                    breadcrumb(viewModel: viewModel)

                    Divider()

                    if let error = viewModel.error {
                        errorState(for: error, viewModel: viewModel)
                    } else if viewModel.isLoading && viewModel.files.isEmpty {
                        skeletonRows
                    } else if viewModel.files.isEmpty {
                        EmptyState(
                            icon: "folder",
                            title: "Empty Folder",
                            message: "Drop files here or use ⌘N to create a folder.",
                            action: .init(label: "New Folder", perform: { viewModel.showNewFolderDialog = true })
                        )
                    } else {
                        switch viewModel.viewMode {
                        case .list:
                            FileTable(
                                files: viewModel.sortedFiles,
                                remote: remoteName,
                                selection: viewModel.selection,
                                keyboard: viewModel.keyboard,
                                sortField: Binding(
                                    get: { viewModel.sortField },
                                    set: { viewModel.sortField = $0 }
                                ),
                                sortAscending: Binding(
                                    get: { viewModel.sortAscending },
                                    set: { viewModel.sortAscending = $0 }
                                ),
                                onOpen: { file in handleOpen(file, viewModel: viewModel) },
                                onContextAction: { file, action in handleAction(file, action, viewModel: viewModel) },
                                onQuickLook: { items in previewFiles(items) }
                            )
                        case .grid:
                            FileGrid(
                                files: viewModel.sortedFiles,
                                remote: remoteName,
                                selection: viewModel.selection,
                                onOpen: { file in handleOpen(file, viewModel: viewModel) },
                                onContextAction: { file, action in handleAction(file, action, viewModel: viewModel) }
                            )
                        }
                    }
                }
                .overlay {
                    if viewModel.isLoading && !viewModel.files.isEmpty {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
                .modifier(BrowserToolbar(
                    viewMode: Binding(
                        get: { viewModel.viewMode },
                        set: { viewModel.viewMode = $0 }
                    ),
                    sortField: Binding(
                        get: { viewModel.sortField },
                        set: { viewModel.sortField = $0 }
                    ),
                    canGoBack: viewModel.canGoBack,
                    canGoForward: viewModel.canGoForward,
                    onBack: { Task { await viewModel.goBack() } },
                    onForward: { Task { await viewModel.goForward() } },
                    onNewFolder: { viewModel.showNewFolderDialog = true },
                    onRefresh: { Task { await viewModel.loadFiles() } }
                ))
                .dropDestination(for: NimbusFileBundle.self) { bundles, _ in
                    let refs = bundles.flatMap(\.refs)
                    return handleDrop(refs: refs, viewModel: viewModel)
                }
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(remoteName)
        .task {
            let vm = BrowserViewModel(client: daemon.client)
            vm.remote = remoteName
            vm.path = initialPath
            viewModel = vm
            await vm.loadFiles()
        }
        .alert("New Folder", isPresented: Binding(
            get: { viewModel?.showNewFolderDialog ?? false },
            set: { viewModel?.showNewFolderDialog = $0 }
        )) {
            TextField("Folder name", text: Binding(
                get: { viewModel?.newFolderName ?? "" },
                set: { viewModel?.newFolderName = $0 }
            ))
            Button("Create") {
                Task {
                    if let viewModel {
                        try? await viewModel.createFolder(name: viewModel.newFolderName)
                        viewModel.newFolderName = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) { viewModel?.newFolderName = "" }
        }
        .alert("Rename", isPresented: Binding(
            get: { viewModel?.renamingFile != nil },
            set: { if !$0 { viewModel?.renamingFile = nil } }
        )) {
            TextField("New name", text: Binding(
                get: { viewModel?.renameText ?? "" },
                set: { viewModel?.renameText = $0 }
            ))
            Button("Rename") {
                if let viewModel, let file = viewModel.renamingFile {
                    Task {
                        try? await viewModel.renameItem(oldPath: file.path, newName: viewModel.renameText)
                        viewModel.renamingFile = nil
                        viewModel.renameText = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel?.renamingFile = nil
                viewModel?.renameText = ""
            }
        }
        .sheet(item: $pendingCopy) { _ in
            ConfirmCopySheet(request: $pendingCopy) { req in
                Task {
                    let coord = makeCoordinator()
                    do {
                        try await coord.apply(
                            .crossRemote(items: req.items, sourceRemote: req.sourceRemote, target: req.target),
                            conflictPolicy: req.conflictPolicy
                        )
                    } catch {
                        Logger(subsystem: "app.casavargas.nimbus", category: "browser")
                            .error("Cross-remote copy failed: \(String(describing: error))")
                    }
                }
            }
        }
    }

    private func makeCoordinator() -> DragDropCoordinator {
        DragDropCoordinator(
            transferStore: transferStore,
            rclone: RcloneClientAdapter(client: daemon.client)
        )
    }

    private func handleDrop(refs: [NimbusFileRef], viewModel: BrowserViewModel) -> Bool {
        let coord = makeCoordinator()
        let target = DropIntent.DropTarget(remote: remoteName, path: viewModel.path)
        do {
            let intent = try coord.resolve(drop: refs, onto: target)
            switch intent {
            case .crossRemote(let items, let sourceRemote, let resolvedTarget):
                pendingCopy = CopyRequest(
                    sourceRemote: sourceRemote,
                    target: resolvedTarget,
                    items: items
                )
                return true
            case .withinRemote, .toFinder:
                // Same-remote drops are handled inline by SwiftUI (move/copy via DnD chrome);
                // Phase 1 doesn't implement in-browser within-remote drag operations beyond
                // what the table/grid handle natively.
                return false
            }
        } catch {
            Logger(subsystem: "app.casavargas.nimbus", category: "browser")
                .warning("Drop resolve error: \(String(describing: error))")
            return false
        }
    }

    private func breadcrumb(viewModel: BrowserViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(component.name) {
                        Task { await viewModel.navigateTo(path: component.path) }
                    }
                    .buttonStyle(.plain)
                    .font(index == viewModel.pathComponents.count - 1 ? .body.bold() : .body)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func handleOpen(_ file: FileItem, viewModel: BrowserViewModel) {
        if file.isDir {
            Task { await viewModel.navigateTo(path: file.path) }
        } else {
            previewFiles([file])
        }
    }

    private func previewFiles(_ items: [FileItem]) {
        Task {
            let provider = QuickLookHost.provider(
                forRemote: remoteName,
                bridge: fileProviderBridge,
                client: RcloneClientAdapter(client: daemon.client)
            )
            await quickLookHost.show(items: items, provider: provider, remote: remoteName)
        }
    }

    private func handleAction(_ file: FileItem, _ action: FileAction, viewModel: BrowserViewModel) {
        switch action {
        case .open:
            handleOpen(file, viewModel: viewModel)
        case .rename:
            viewModel.renamingFile = file
            viewModel.renameText = file.name
        case .delete:
            Task { try? await viewModel.deleteItems(paths: [file.path]) }
        case .bookmark:
            let label = file.name.isEmpty ? file.path : file.name
            bookmarkStore.addBookmark(remoteName: remoteName, path: file.path, label: label)
        case .download:
            // Will use NSFileProviderManager when wired up
            break
        case .evict:
            // Will use NSFileProviderManager when wired up
            break
        }
    }

    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: DesignSystem.Spacing.s) {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                        .frame(height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                        .frame(width: 60, height: 10)
                }
                .padding(.horizontal, DesignSystem.Spacing.m)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .redacted(reason: .placeholder)
            }
            Spacer()
        }
        .shimmering()
        .accessibilityLabel("Loading folder contents")
    }

    @ViewBuilder
    private func errorState(for error: BrowserError, viewModel: BrowserViewModel) -> some View {
        switch error.kind {
        case .authFailed:
            EmptyState(
                icon: "key.slash",
                title: "Sign In Required",
                messageVerbatim: "\(remoteName): \(error.message)",
                action: .init(label: "Reconnect Remote", perform: {
                    // Navigate to Remotes screen — implementation can hook into a
                    // navigation environment value if one exists; for Phase 1, a
                    // simple no-op + log is acceptable.
                    Logger(subsystem: "app.casavargas.nimbus", category: "browser")
                        .info("Reconnect Remote tapped for \(remoteName)")
                })
            )
        case .network:
            EmptyState(
                icon: "wifi.slash",
                title: "Can't Reach Cloud",
                messageVerbatim: error.message,
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadFiles() }
                })
            )
        case .other:
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't Load Folder",
                messageVerbatim: error.message,
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadFiles() }
                })
            )
        }
    }
}
