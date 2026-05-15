import SwiftUI
import RcloneKit
import os

struct RemotesView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppSettings.self) private var settings
    var onBrowse: ((String) -> Void)?
    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
    @State private var showImportConfig = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?
    @State private var searchText = ""
    @State private var listSelection: String?

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
                ToolbarItem(placement: .secondaryAction) {
                    Button("Import Config", systemImage: "square.and.arrow.down") {
                        showImportConfig = true
                    }
                    .disabled(daemon.status != .connected)
                }
            }
            .searchable(text: $searchText, placement: .toolbar)
            .task(id: daemon.status) {
                guard daemon.status == .connected else { return }
                if viewModel == nil {
                    viewModel = RemotesViewModel(client: daemon.client)
                }
                await viewModel?.loadRemotes()
            }
            // Sheet call sites preserved from Phase 1; Tasks 4-6 will rebuild these.
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
                Button("Cancel", role: .cancel) { deletingRemote = nil }
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
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Could not start rclone",
                messageVerbatim: message,
                action: .init(label: "Retry", perform: {
                    Task { await daemon.retry(binaryPath: settings.rcloneBinaryPath) }
                })
            )

        case .connected:
            if let viewModel {
                connectedContent(viewModel: viewModel)
            } else {
                // Connected but viewModel not yet initialised (very brief window)
                ProgressView("Loading remotes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func connectedContent(viewModel: RemotesViewModel) -> some View {
        if let error = viewModel.error, viewModel.remotes.isEmpty {
            errorBanner(error: error, viewModel: viewModel)
        } else if viewModel.isLoading && viewModel.remotes.isEmpty {
            skeletonList
        } else if viewModel.remotes.isEmpty {
            EmptyState(
                icon: "cloud.slash",
                title: "No Remotes Yet",
                message: "Add a remote to start browsing cloud storage.",
                action: .init(label: "Add Remote", perform: { showAddRemote = true })
            )
        } else {
            List(filteredRemotes(viewModel.remotes), id: \.name, selection: $listSelection) { remote in
                RemoteRow(
                    remote: remote,
                    status: .connected, // Phase 2a placeholder; richer status discovery is Phase 3
                    onEdit: { editingRemote = remote },
                    onDelete: { deletingRemote = remote },
                    onBrowse: { onBrowse?(remote.name) },
                    onReconnect: {
                        Logger(subsystem: "app.casavargas.nimbus", category: "remotes")
                            .warning("Reconnect handler not wired (Phase 3); status is hardcoded to .connected in Phase 2a so this should be unreachable")
                    }
                )
                .tag(remote.name)
            }
            .listStyle(.inset)
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: DesignSystem.Spacing.m) {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .fill(DesignSystem.Color.semantic.surfaceSubtle)
                            .frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .fill(DesignSystem.Color.semantic.surfaceSubtle)
                            .frame(width: 60, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.m)
                .padding(.vertical, DesignSystem.Spacing.s)
                .redacted(reason: .placeholder)
            }
            Spacer()
        }
        .shimmering()
    }

    @ViewBuilder
    private func errorBanner(error: NimbusError, viewModel: RemotesViewModel) -> some View {
        switch error.kind {
        case .authFailed:
            EmptyState(
                icon: "key.slash",
                title: "Sign In Required",
                messageVerbatim: error.message,
                action: .init(label: "Reconnect", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        case .network:
            EmptyState(
                icon: "wifi.slash",
                title: "Can't Reach Cloud",
                messageVerbatim: error.message,
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        case .other:
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't Load Remotes",
                messageVerbatim: error.message,
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        }
    }

    private func filteredRemotes(_ remotes: [Remote]) -> [Remote] {
        guard !searchText.isEmpty else { return remotes }
        let q = searchText.lowercased()
        return remotes.filter {
            $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q)
        }
    }
}
