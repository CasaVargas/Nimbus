import SwiftUI
import RcloneKit

struct RemotesView: View {
    @Environment(RcloneDaemon.self) private var daemon
    var onBrowse: ((String) -> Void)?
    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
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
        if let viewModel {
            if viewModel.isLoading && viewModel.remotes.isEmpty {
                ProgressView("Loading remotes...")
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
