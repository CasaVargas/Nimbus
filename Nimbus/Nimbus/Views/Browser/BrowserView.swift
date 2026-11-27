import SwiftUI
import RcloneKit
import os

struct BrowserView: View {
    let remoteName: String
    var initialPath: String = ""
    /// When this changes and its `remote` matches `remoteName`, the browser
    /// navigates to `path` on the live view model (no view recreation).
    var browseTarget: BrowseTarget?
    /// False while another volume tab is in front: the browser's toolbar
    /// items and menu actions step aside so ⌘N can't create folders from
    /// the Settings tab.
    var showsToolbar: Bool = true
    /// Optional model owned by the parent (the volume pane shares it with
    /// the inspector). When nil the browser creates and owns its own.
    var sharedModel: BrowserViewModel? = nil
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppSettings.self) private var settings
    @Environment(BookmarkStore.self) private var bookmarkStore
    @Environment(TransferStore.self) private var transferStore
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @Environment(RemoteStatusService.self) private var statusService
    /// Optional: the browser is also hosted where no monitor is installed.
    @Environment(CloudMonitor.self) private var monitor: CloudMonitor?
    @State private var viewModel: BrowserViewModel?
    @State private var pendingCopy: CopyRequest?
    /// Local files dropped on the browser, waiting on the Send sheet.
    @State private var pendingSend: SendRequest?
    @State private var quickLookHost = QuickLookHost()
    /// Draws the gallery's pictures. Made with the view model, once the
    /// daemon client is known.
    @State private var thumbnailLoader: BrowserThumbnailLoader?
    @State private var actionError: ActionError?

    private struct ActionError: Equatable {
        let title: String
        let message: String
    }

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
                            .overlay(alignment: .bottom) {
                                if viewModel.isSlow { slowNotice }
                            }
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
                        case .gallery:
                            FileGallery(
                                files: viewModel.sortedFiles,
                                remote: remoteName,
                                selection: viewModel.selection,
                                thumbnails: thumbnailLoader,
                                onOpen: { file in handleOpen(file, viewModel: viewModel) },
                                onContextAction: { file, action in handleAction(file, action, viewModel: viewModel) },
                                onQuickLook: { items in previewFiles(items) }
                            )
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if ShareHost.shared.isPreparing {
                        Label("Getting ready to share…", systemImage: "square.and.arrow.up")
                            .font(DesignSystem.Typography.callout)
                            .padding(.horizontal, DesignSystem.Spacing.m)
                            .padding(.vertical, DesignSystem.Spacing.s)
                            .background(.regularMaterial, in: Capsule())
                            .padding(DesignSystem.Spacing.l)
                            .transition(.opacity)
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
                .modifier(Conditional(enabled: showsToolbar, modifier: BrowserToolbar(
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
                )))
                .dropDestination(for: BrowserDrop.self) { drops, _ in
                    let (refs, urls) = BrowserDrop.split(drops)
                    // Files from Finder: ask where they go, with this folder filled in.
                    if let request = SendRequest(urls: urls) {
                        pendingSend = request
                        return true
                    }
                    return handleDrop(refs: refs, viewModel: viewModel)
                }
                .focusedSceneValue(\.browserActions, !showsToolbar ? nil : BrowserMenuActions(
                    canGoBack: viewModel.canGoBack,
                    canGoForward: viewModel.canGoForward,
                    viewMode: viewModel.viewMode,
                    goBack: { Task { await viewModel.goBack() } },
                    goForward: { Task { await viewModel.goForward() } },
                    newFolder: { viewModel.showNewFolderDialog = true },
                    refresh: {
                        Task { await viewModel.loadFiles() }
                        // ⌘R refreshes this cloud in Finder too.
                        let remote = remoteName
                        Task { await FileProviderBridge.signalWorkingSets(remote: remote) }
                    },
                    setViewMode: { viewModel.viewMode = $0 }
                ))
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(remoteName)
        .task {
            let vm = sharedModel ?? BrowserViewModel(client: daemon.client)
            if vm.remote.isEmpty {
                vm.remote = remoteName
                vm.path = initialPath
            }
            viewModel = vm
            if thumbnailLoader == nil {
                thumbnailLoader = BrowserThumbnailLoader(
                    client: RcloneClientAdapter(client: daemon.client),
                    cache: BrowserThumbnailLoader.defaultCache()
                )
            }
            await vm.loadFiles()
        }
        .onChange(of: browseTarget) { _, newValue in
            // browseTarget is a one-shot trigger for an IN-REMOTE jump on the
            // already-live browser. A CROSS-REMOTE jump recreates this view
            // (.id(remote) in ContentView) and is seeded via initialPath in
            // .task instead — .onChange does not fire on a fresh view's first
            // value, so there's no double-load. If a target somehow arrives
            // before .task builds the view model, the guard drops it (the
            // cross-remote/initialPath path covers first load).
            guard let target = newValue, target.remote == remoteName,
                  let viewModel else { return }
            Task { await viewModel.navigateTo(path: target.path) }
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
                if let viewModel {
                    let name = viewModel.newFolderName
                    viewModel.newFolderName = ""
                    Task {
                        do {
                            try await viewModel.createFolder(name: name)
                        } catch {
                            actionError = ActionError(title: "Couldn't Create Folder", message: NimbusError.classify(error).message)
                        }
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
                    let newName = viewModel.renameText
                    viewModel.renamingFile = nil
                    viewModel.renameText = ""
                    Task {
                        do {
                            try await viewModel.renameItem(oldPath: file.path, newName: newName)
                        } catch {
                            actionError = ActionError(title: "Couldn't Rename", message: NimbusError.classify(error).message)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel?.renamingFile = nil
                viewModel?.renameText = ""
            }
        }
        .alert(
            actionError?.title ?? "Couldn't Complete Action",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) { actionError = nil }
        } message: { current in
            Text(verbatim: current.message)
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
        .sheet(item: $pendingSend) { request in
            SendToNimbusSheet(
                request: request,
                remoteNames: sendDestinations,
                lastRemote: remoteName,
                lastPath: viewModel?.path ?? "",
                client: daemon.client,
                onAddCloud: {},
                onSent: { _, _ in }
            )
        }
        // A transfer touching this cloud finished: what it brought is listed.
        .onChange(of: activeTransferCount) { old, new in
            guard new < old, let viewModel else { return }
            Task { await viewModel.loadFiles() }
        }
    }

    private var activeTransferCount: Int {
        transferStore.activeTransfers.count { $0.involves(remote: remoteName) }
    }

    /// Clouds the Send sheet offers for a Finder drop: this one first.
    private var sendDestinations: [String] {
        [remoteName] + (monitor?.remotes.map(\.name) ?? []).filter { $0 != remoteName }
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
                    items: items,
                    conflictPolicy: settings.defaultConflictPolicy
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
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    }
                    Button {
                        Task { await viewModel.navigateTo(path: component.path) }
                    } label: {
                        if index == 0 {
                            Label(remoteName, systemImage: "cloud")
                        } else {
                            Text(component.name)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(index == viewModel.pathComponents.count - 1
                          ? DesignSystem.Typography.bodyEmphasized
                          : DesignSystem.Typography.body)
                    .foregroundStyle(index == viewModel.pathComponents.count - 1
                                     ? DesignSystem.Color.semantic.textPrimary : DesignSystem.Color.semantic.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.l)
            .frame(height: 38)
        }
        .accessibilityLabel("Current folder")
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
            Task {
                do {
                    try await viewModel.deleteItems(paths: [file.path])
                } catch {
                    actionError = ActionError(title: "Couldn't Delete", message: NimbusError.classify(error).message)
                }
            }
        case .bookmark:
            let label = file.name.isEmpty ? file.path : file.name
            bookmarkStore.addBookmark(remoteName: remoteName, path: file.path, label: label)
        case .download:
            // Will use NSFileProviderManager when wired up
            break
        case .evict:
            // Will use NSFileProviderManager when wired up
            break
        case .share:
            // Sharing a file that's part of the selection shares all of it.
            let selected = viewModel.sortedFiles.filter { viewModel.selection.ids.contains($0.id) }
            let items = selected.contains { $0.id == file.id } ? selected : [file]
            let client = RcloneClientAdapter(client: daemon.client)
            Task { await ShareHost.shared.share(items, remote: remoteName, client: client) }
        }
    }

    /// Shown once a listing has run long, so a slow answer doesn't look
    /// like a hang. Names the cause when it's the shared Google sign-in.
    private var slowNotice: some View {
        let shared = monitor?.remotes.first { $0.name == remoteName }.map(SharedGoogleClientID.isUsed(by:)) ?? false
        return Label(Self.slowText(usesSharedGoogleID: shared), systemImage: "hourglass")
            .font(DesignSystem.Typography.callout)
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            .multilineTextAlignment(.center)
            .padding(DesignSystem.Spacing.l)
            .transition(.opacity)
    }

    static func slowText(usesSharedGoogleID: Bool) -> String {
        usesSharedGoogleID
            ? "Still loading. Google is limiting the shared sign-in this cloud uses; Home has a fix."
            : "Still loading…"
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
                action: .init(label: "Try Again", perform: {
                    // Re-probe the remote (refreshes token state via rclone)
                    // and reload. If credentials are truly dead, the error
                    // state returns with rclone's message.
                    Task {
                        await statusService.probe(remoteName)
                        await viewModel.loadFiles()
                    }
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
