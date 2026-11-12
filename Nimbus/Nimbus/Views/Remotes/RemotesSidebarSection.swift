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
    @State private var showEncryptedFolder = false
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
            }
            // The one place to add a cloud: a row where the new cloud will
            // appear, on every screen. It replaced a small plus in the
            // header and two more Add Cloud buttons on Home.
            SidebarAddCloudRow { showAddRemote = true }
                .disabled(daemon.status != .connected)
                .contextMenu {
                    Button("Add Cloud…", systemImage: "plus") { showAddRemote = true }
                    Button("New Encrypted Folder…", systemImage: "lock.rectangle.stack") { showEncryptedFolder = true }
                    Button("Import from rclone.conf…", systemImage: "square.and.arrow.down") { showImportConfig = true }
                }
                // Presentations hang off this one row, never the Section: in a
                // List, a Section's modifiers are copied onto every row, so one
                // binding opened a stacked sheet per cloud (+1 for this row).
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
                .sheet(isPresented: $showEncryptedFolder) {
                    EncryptedFolderSheet(client: daemon.client, remoteNames: monitor.remotes.map(\.name),
                                         onDismiss: { Task { await monitor.refresh() } })
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
        } header: {
            Text("Clouds")
        }
    }
}

/// The last row of the Clouds section: an empty, dashed tile where the next
/// cloud's logo will go, and "Add Cloud…". Same height and rhythm as
/// `SidebarRemoteRow`.
struct SidebarAddCloudRow: View {
    let action: () -> Void

    @Environment(\.stratosphere) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.s) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.textTertiary.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "plus")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .frame(width: 10, height: 10)
                            .foregroundStyle(palette.textSecondary.color)
                    }
                    .accessibilityHidden(true)
                Text("Add Cloud…")
                    .font(DesignSystem.Stratosphere.Typography.control)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .help("Add a cloud. Right-click to import from rclone.conf.")
    }
}
