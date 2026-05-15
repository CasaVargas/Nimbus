import SwiftUI
import RcloneKit

struct BrowserView: View {
    let remoteName: String
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(BookmarkStore.self) private var bookmarkStore
    @State private var viewModel: BrowserViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VStack(spacing: 0) {
                    breadcrumb(viewModel: viewModel)

                    Divider()

                    if viewModel.isLoading && viewModel.files.isEmpty {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.files.isEmpty {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "folder",
                            description: Text("This folder has no files.")
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
                                onQuickLook: { items in
                                    // Quick Look wiring deferred to Task 9/10 environment integration.
                                    // For Task 8, just no-op (log for manual verification).
                                    print("Quick Look requested for \(items.count) items")
                                }
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
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(remoteName)
        .task {
            let vm = BrowserViewModel(client: daemon.client)
            vm.remote = remoteName
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
    }

    private func breadcrumb(viewModel: BrowserViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
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
}
