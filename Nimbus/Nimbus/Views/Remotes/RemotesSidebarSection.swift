import SwiftUI
import RcloneKit

/// The REMOTES section of the sidebar. Loads remotes, probes their status,
/// owns the add/import/edit/delete UI, and tells the parent which remotes
/// exist so selection can be reconciled.
struct RemotesSidebarSection: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService

    /// Called every time the remote list (re)loads, with the current remotes.
    var onRemotesLoaded: ([Remote]) -> Void

    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
    @State private var showImportConfig = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?

    var body: some View {
        Section {
            if let viewModel, !viewModel.remotes.isEmpty {
                ForEach(viewModel.remotes, id: \.name) { remote in
                    SidebarRemoteRow(
                        remote: remote,
                        status: statusService.statuses[remote.name] ?? .unknown,
                        quota: statusService.quotas[remote.name],
                        iconType: CloudNaming.resolvedType(of: remote, in: viewModel.remotes),
                        onEdit: { editingRemote = remote },
                        onDelete: { deletingRemote = remote },
                        onReconnect: { Task { await statusService.probe(remote.name) } }
                    )
                    .tag(SidebarSelection.remote(remote.name))
                }
            } else if daemon.status == .connected {
                Button {
                    showAddRemote = true
                } label: {
                    Label("Add Cloud…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Clouds")
                Spacer()
                Menu {
                    Button("Add Cloud…", systemImage: "plus") { showAddRemote = true }
                    Button("Import from rclone.conf…", systemImage: "square.and.arrow.down") { showImportConfig = true }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(daemon.status != .connected)
                .help("Add a cloud or import one from rclone.conf")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nimbusRemotesChanged)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nimbusAddCloudRequested)) { _ in
            guard daemon.status == .connected else { return }
            showAddRemote = true
        }
        .task(id: daemon.status) {
            // Reconciliation (onRemotesLoaded) fires only on a real list
            // (re)load while connected. We deliberately do NOT fire it on
            // daemon disconnect: that would feed nextSelection an empty list
            // and deselect the user's remote on a transient hiccup. Daemon
            // errors are surfaced in-pane by BrowserView, not by changing
            // the sidebar selection.
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = RemotesViewModel(client: daemon.client)
            }
            await reload()
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(client: daemon.client, onDismiss: { Task { await reload() } })
        }
        .sheet(isPresented: $showImportConfig) {
            ImportConfigSheet(onDismiss: { Task { await reload() } })
        }
        .sheet(isPresented: Binding(
            get: { editingRemote != nil },
            set: { if !$0 { editingRemote = nil } }
        )) {
            if let remote = editingRemote {
                EditRemoteSheet(client: daemon.client, remote: remote,
                                onDismiss: { Task { await reload() } })
            }
        }
        .confirmationDialog(
            "Remove \(deletingRemote?.name ?? "") from Nimbus?",
            isPresented: Binding(
                get: { deletingRemote != nil },
                set: { if !$0 { deletingRemote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let remote = deletingRemote {
                    let name = remote.name
                    Task {
                        await viewModel?.deleteRemote(name: name)
                        statusService.clear(name)
                        await reload()
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletingRemote = nil }
        } message: {
            Text("Nimbus forgets how to reach this cloud. Files stored in the cloud aren't affected.")
        }
    }

    private func reload() async {
        guard let viewModel else { return }
        await viewModel.loadRemotes()
        let names = viewModel.remotes.map(\.name)
        // Report first, probe second: probing can block for seconds on a
        // remote with an expired token, and the detail pane must not sit on
        // "No Remotes Yet" while the sidebar already lists them.
        onRemotesLoaded(viewModel.remotes)
        if !names.isEmpty { await statusService.probeAll(names) }
    }
}
