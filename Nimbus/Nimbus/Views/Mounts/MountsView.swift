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

    /// When set, only this remote's configurations are shown and the pane
    /// header is omitted (the volume pane's Finder tab).
    var remoteFilter: String? = nil

    @State private var viewModel: MountsViewModel?
    @State private var showingAddSheet = false
    @State private var editingConfig: MountConfig?
    @State private var deletingConfig: MountConfig?
    @State private var expandedID: String?
    @State private var error: NimbusError?

    var body: some View {
        content
            .navigationTitle(remoteFilter ?? "Finder")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add to Finder", systemImage: "plus") { showingAddSheet = true }
                        .disabled(daemon.status != .connected || viewModel == nil)
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
                // A remote shown in Finder by default (the launch-time domain
                // sync registers every remote not explicitly hidden) has no
                // configuration record yet; write one so the Finder tab shows
                // the switch that matches what Finder is already doing.
                if let remoteFilter, FinderIntegration.isShown(remote: remoteFilter, settings: settings) {
                    FinderIntegration.ensureConfig(remote: remoteFilter, store: configs, settings: settings)
                }
                mountManager.configs = configs.configs
                await mountManager.refreshAll()
            }
            .sheet(isPresented: $showingAddSheet) {
                if let viewModel {
                    AddMountSheet(viewModel: viewModel, initialRemote: remoteFilter)
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
                Text("Nimbus disconnects it from Finder and forgets this setup. Files in the cloud aren't affected.")
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
        VStack(spacing: 0) {
            if remoteFilter == nil {
                finderHeader
                Divider()
            }
            if visibleConfigs.isEmpty {
                if remoteFilter == nil {
                    EmptyState(
                        icon: "macwindow.badge.plus",
                        title: "Bring a Cloud into Finder",
                        message: "Show a cloud as a Finder location. Files download when you open them, and macOS manages the space.",
                        action: .init(label: "Add to Finder", perform: { showingAddSheet = true })
                    )
                } else {
                    EmptyState(
                        icon: "macwindow.badge.plus",
                        title: "Not in Finder Yet",
                        message: "Show this cloud beside iCloud Drive, or connect it as a network drive with the + button.",
                        action: .init(label: "Show in Finder", perform: { Task { await showInFinder() } })
                    )
                }
            } else {
                list
            }
        }
    }

    private var visibleConfigs: [MountConfig] {
        guard let remoteFilter else { return configs.configs }
        return configs.configs.filter { $0.remoteNameOnly == remoteFilter }
    }

    private func showInFinder() async {
        guard let remoteFilter else { return }
        do {
            try await FinderIntegration.show(remote: remoteFilter, settings: settings, bridge: fileProviderBridge)
            FinderIntegration.ensureConfig(remote: remoteFilter, store: configs, settings: settings)
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private var finderHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
            Image(systemName: "folder.badge.gearshape")
                .font(DesignSystem.Typography.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finder Locations")
                    .font(DesignSystem.Typography.headline)
                Text("Cloud files appear in Finder and download only when you open them.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            Spacer()
            if !configs.configs.isEmpty {
                Text("\(configs.configs.count) configured")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .frame(minHeight: 64)
        .background(DesignSystem.Color.semantic.surfaceSubtle.opacity(0.45))
    }

    private var list: some View {
        List {
            ForEach(visibleConfigs) { config in
                VStack(spacing: 0) {
                    MountRow(
                        config: config,
                        state: state(for: config),
                        onToggle: { Task { await toggle(config: config) } },
                        onRevealInFinder: { Task { await revealInFinder(config: config) } },
                        onEdit: { editingConfig = config },
                        onDelete: { deletingConfig = config },
                        inCloudPane: remoteFilter != nil
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
        switch config.backend {
        case .nfs:
            if mountManager.mountedIDs.contains(config.id) { return true }
            return mountManager.activeMounts.contains { $0.mountPoint == config.mountPoint }
        case .fileProvider:
            // Drive the switch from the user's persisted intent, NOT the
            // live `NSFileProviderManager.domains()` snapshot. That snapshot
            // is eventually consistent (add/remove lag) and is also rewritten
            // by the 10s health monitor and the daemon-reconnect sync, so
            // reading it made the switch snap back and flip-flop right after
            // a toggle. Intent is synchronous and stable; the actual domain
            // registration is reconciled against it in the background.
            return !settings.disabledFileProviderDomains.contains(config.remoteNameOnly)
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
                // Intent flips first, registration reconciles later; see
                // FinderIntegration for the reasoning and the rollback.
                if isMountActive(config) {
                    try await FinderIntegration.hide(remote: name, settings: settings, bridge: fileProviderBridge)
                } else {
                    try await FinderIntegration.show(remote: name, settings: settings, bridge: fileProviderBridge)
                }
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

    private func revealInFinder(config: MountConfig) async {
        switch config.backend {
        case .fileProvider:
            if let url = await fileProviderBridge.urlForItem(remote: config.remoteNameOnly, path: "") {
                NSWorkspace.shared.open(url)
            }
        case .nfs:
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: config.mountPoint)]
            )
        }
    }
}
