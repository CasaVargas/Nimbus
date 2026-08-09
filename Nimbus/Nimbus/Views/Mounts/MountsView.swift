import SwiftUI
import AppKit
import RcloneKit

/// Mounts list — rebuilt against the Phase 2a foundation.
/// Reference: macOS System Settings · Login Items (row layout), Disk Utility
/// (inline inspector pattern).
struct MountsView: View {
    @Environment(MountManager.self) private var mountManager
    @Environment(MountConfigStore.self) private var configs
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @Environment(AppSettings.self) private var settings

    @State private var viewModel: MountsViewModel?
    @State private var showingAddSheet = false
    @State private var editingConfig: MountConfig?
    @State private var deletingConfig: MountConfig?
    @State private var expandedID: String?
    @State private var error: NimbusError?

    var body: some View {
        content
            .navigationTitle("Mounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mount", systemImage: "plus") { showingAddSheet = true }
                        .disabled(daemon.status != .connected || viewModel == nil)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            mountManager.configs = configs.configs
                            await mountManager.refreshAll()
                        }
                    }
                }
            }
            .task(id: daemon.status) {
                guard daemon.status == .connected else { return }
                if viewModel == nil {
                    viewModel = MountsViewModel(client: daemon.client)
                }
                await viewModel?.loadRemotes()
            }
            .task {
                mountManager.configs = configs.configs
                await mountManager.refreshAll()
            }
            .sheet(isPresented: $showingAddSheet) {
                if let viewModel {
                    AddMountSheet(viewModel: viewModel)
                }
            }
            .sheet(item: $editingConfig) { config in
                if let viewModel {
                    AddMountSheet(viewModel: viewModel, editing: config)
                }
            }
            .confirmationDialog(
                "Delete this mount?",
                isPresented: Binding(
                    get: { deletingConfig != nil },
                    set: { if !$0 { deletingConfig = nil } }
                ),
                presenting: deletingConfig
            ) { config in
                Button("Delete", role: .destructive) {
                    Task { await deleteConfig(config) }
                }
                Button("Cancel", role: .cancel) { deletingConfig = nil }
            } message: { _ in
                Text("This will unmount the volume if mounted and remove the configuration.")
            }
            .alert(
                "Mount error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                ),
                presenting: error
            ) { _ in
                Button("OK", role: .cancel) { error = nil }
            } message: { err in
                Text(verbatim: err.message)
            }
    }

    @ViewBuilder
    private var content: some View {
        if configs.configs.isEmpty {
            EmptyState(
                icon: "externaldrive",
                title: "No Mounts Configured",
                message: "Mount a remote to access it as a local volume.",
                action: .init(label: "Add Mount", perform: { showingAddSheet = true })
            )
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(configs.configs) { config in
                VStack(spacing: 0) {
                    MountRow(
                        config: config,
                        state: state(for: config),
                        onToggle: { Task { await toggle(config: config) } },
                        onRevealInFinder: { revealInFinder(config: config) },
                        onEdit: { editingConfig = config },
                        onDelete: { deletingConfig = config }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(DesignSystem.Motion.smooth) {
                            expandedID = expandedID == config.id ? nil : config.id
                        }
                    }
                    if expandedID == config.id {
                        MountInspector(
                            config: config,
                            lastMountedAt: mountManager.lastMounted[config.id]
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - State derivation

    private func state(for config: MountConfig) -> StatusToggleState {
        if let reason = mountManager.errors[config.id] {
            return .error(reason: reason)
        }
        let isMounted = isMountActive(config)
        if mountManager.inFlight.contains(config.id) {
            return isMounted ? .unmounting : .mounting
        }
        return isMounted ? .on : .off
    }

    /// Source-of-truth derivation: union of MountManager's tracked IDs with the
    /// in-process `activeMounts` list (mountPoint match) and the
    /// FileProvider bridge's active domains. This keeps legacy code paths
    /// (NimbusApp auto-mount loop) working without needing them to call the new
    /// `mountConfig` wrapper.
    private func isMountActive(_ config: MountConfig) -> Bool {
        if mountManager.mountedIDs.contains(config.id) { return true }
        switch config.backend {
        case .nfs:
            return mountManager.activeMounts.contains { $0.mountPoint == config.mountPoint }
        case .fileProvider:
            return fileProviderBridge.activeDomains.contains(config.remoteNameOnly)
        }
    }

    // MARK: - Actions

    private func toggle(config: MountConfig) async {
        do {
            switch config.backend {
            case .nfs:
                if isMountActive(config) {
                    try await mountManager.unmountConfig(config)
                } else {
                    try await mountManager.mountConfig(config)
                }
            case .fileProvider:
                let name = config.remoteNameOnly
                if isMountActive(config) {
                    try await fileProviderBridge.removeDomain(identifier: name)
                    // Remember the choice — the launch-time domain sync
                    // re-registers every remote it isn't told to skip.
                    settings.disabledFileProviderDomains.insert(name)
                } else {
                    try await fileProviderBridge.addDomain(identifier: name, displayName: name)
                    settings.disabledFileProviderDomains.remove(name)
                }
                await fileProviderBridge.refreshDomains()
            }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private func deleteConfig(_ config: MountConfig) async {
        if isMountActive(config) {
            switch config.backend {
            case .nfs:
                try? await mountManager.unmountConfig(config)
            case .fileProvider:
                try? await fileProviderBridge.removeDomain(identifier: config.remoteNameOnly)
                settings.disabledFileProviderDomains.insert(config.remoteNameOnly)
                await fileProviderBridge.refreshDomains()
            }
        }
        configs.removeConfig(id: config.id)
        deletingConfig = nil
    }

    private func revealInFinder(config: MountConfig) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: config.mountPoint)]
        )
    }
}
