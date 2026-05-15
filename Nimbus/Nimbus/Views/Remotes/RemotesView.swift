import SwiftUI
import RcloneKit

struct RemotesView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppSettings.self) private var settings
    var onBrowse: ((String) -> Void)?
    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
    @State private var showImportConfig = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?

    var body: some View {
        content
            .navigationTitle("Remotes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Remote", systemImage: "plus") {
                        showAddRemote = true
                    }
                    // Only allow adding remotes once the daemon is reachable
                    .disabled(daemon.status != .connected)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import Config", systemImage: "square.and.arrow.down") {
                        showImportConfig = true
                    }
                    .disabled(daemon.status != .connected)
                }
            }
            .task(id: daemon.status) {
                guard daemon.status == .connected else { return }
                if viewModel == nil {
                    viewModel = RemotesViewModel(client: daemon.client)
                }
                await viewModel?.loadRemotes()
            }
            .sheet(isPresented: $showAddRemote) {
                AddRemoteSheet(onComplete: {
                    Task { await viewModel?.loadRemotes() }
                })
            }
            .sheet(isPresented: $showImportConfig) {
                ImportConfigSheet(onComplete: {
                    Task { await viewModel?.loadRemotes() }
                })
            }
            .sheet(isPresented: Binding(
                get: { editingRemote != nil },
                set: { if !$0 { editingRemote = nil } }
            )) {
                if let remote = editingRemote {
                    EditRemoteSheet(remote: remote, onComplete: {
                        Task { await viewModel?.loadRemotes() }
                    })
                }
            }
            .confirmationDialog(
                "Delete \(deletingRemote?.name ?? "")?",
                isPresented: Binding(
                    get: { deletingRemote != nil },
                    set: { if !$0 { deletingRemote = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let remote = deletingRemote {
                        Task { await viewModel?.deleteRemote(name: remote.name) }
                    }
                }
            } message: {
                Text("This will remove the remote configuration. Files on the cloud are not affected.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch daemon.status {
        case .idle, .starting:
            // Daemon is still starting up — show a labelled spinner
            ProgressView("Connecting to rclone...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            // Daemon failed to start — give the user a clear error and a retry button
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Could not start rclone")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") {
                    Task { await daemon.retry(binaryPath: settings.rcloneBinaryPath) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .connected:
            if let viewModel {
                if viewModel.isLoading && viewModel.remotes.isEmpty {
                    ProgressView("Loading remotes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.remotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Failed to load remotes")
                            .font(.headline)
                        Text(error.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task { await viewModel.loadRemotes() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.remotes.isEmpty {
                    ContentUnavailableView(
                        "No Remotes",
                        systemImage: "cloud",
                        description: Text("Add a cloud remote to get started.")
                    )
                } else {
                    List(viewModel.remotes, id: \.name) { remote in
                        RemoteRow(
                            remote: remote,
                            onEdit: { editingRemote = remote },
                            onDelete: { deletingRemote = remote },
                            onBrowse: { onBrowse?(remote.name) }
                        )
                    }
                }
            } else {
                // Connected but viewModel not yet initialised (very brief window)
                ProgressView("Loading remotes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
