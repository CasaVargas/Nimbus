import SwiftUI
import RcloneKit

/// The Clouds section of the sidebar. Lists the app-wide `CloudMonitor`'s
/// clouds and owns the add/import/edit/remove UI; loading and probing live
/// in the monitor so the menu bar sees the same list with the window closed.
struct RemotesSidebarSection: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(CloudMonitor.self) private var monitor
    @Environment(AppRouter.self) private var router

    @State private var showAddRemote = false
    @State private var showImportConfig = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?

    var body: some View {
        Section {
            if !monitor.remotes.isEmpty {
                ForEach(monitor.remotes, id: \.name) { remote in
                    SidebarRemoteRow(
                        remote: remote,
                        status: statusService.statuses[remote.name] ?? .unknown,
                        quota: statusService.quotas[remote.name],
                        iconType: CloudNaming.resolvedType(of: remote, in: monitor.remotes),
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
        .onChange(of: router.pending, initial: true) {
            guard daemon.status == .connected,
                  router.take(where: { $0 == .addCloud }) != nil else { return }
            showAddRemote = true
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(client: daemon.client, onDismiss: { Task { await monitor.refresh() } })
        }
        .sheet(isPresented: $showImportConfig) {
            ImportConfigSheet(onDismiss: { Task { await monitor.refresh() } })
        }
        .sheet(isPresented: Binding(
            get: { editingRemote != nil },
            set: { if !$0 { editingRemote = nil } }
        )) {
            if let remote = editingRemote {
                EditRemoteSheet(client: daemon.client, remote: remote,
                                onDismiss: { Task { await monitor.refresh() } })
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
                        await monitor.remove(name, client: daemon.client)
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletingRemote = nil }
        } message: {
            Text("Nimbus forgets how to reach this cloud. Files stored in the cloud aren't affected.")
        }
    }
}
