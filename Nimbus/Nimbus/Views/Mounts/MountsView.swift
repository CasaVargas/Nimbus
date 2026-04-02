import SwiftUI
import RcloneKit

struct MountsView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var configStore
    @Environment(MountManager.self) private var mountManager
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @State private var viewModel: MountsViewModel?
    @State private var showAddMount = false

    var body: some View {
        content
            .navigationTitle("Mounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mount", systemImage: "plus") {
                        showAddMount = true
                    }
                    .disabled(viewModel == nil)
                }
            }
            .task(id: daemon.status) {
                guard daemon.status == .connected else { return }
                if viewModel == nil {
                    viewModel = MountsViewModel(client: daemon.client)
                }
                await viewModel?.loadRemotes()
            }
            .sheet(isPresented: $showAddMount) {
                if let viewModel {
                    AddMountSheet(viewModel: viewModel)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if configStore.configs.isEmpty {
            ContentUnavailableView(
                "No Mounts",
                systemImage: "externaldrive",
                description: Text("Add a mount to access cloud files as a local drive.")
            )
        } else {
            List(configStore.configs) { config in
                let isActive = isMountActive(config)
                MountRow(
                    config: config,
                    isActive: isActive,
                    onToggle: { Task { await toggleMount(config: config, isActive: isActive) } },
                    onRemove: { Task { await removeMount(config: config) } }
                )
            }
        }
    }

    private func isMountActive(_ config: MountConfig) -> Bool {
        switch config.backend {
        case .nfs:
            mountManager.activeMounts.contains { $0.mountPoint == config.mountPoint }
        case .fileProvider:
            fileProviderBridge.activeDomains.contains(config.remoteNameOnly)
        }
    }

    private func toggleMount(config: MountConfig, isActive: Bool) async {
        switch config.backend {
        case .nfs:
            if isActive {
                try? await mountManager.unmount(mountPoint: config.mountPoint)
            } else {
                try? await mountManager.mount(
                    remote: config.remote,
                    mountPoint: config.mountPoint,
                    readOnly: config.vfsMode == .readOnly
                )
            }
        case .fileProvider:
            let name = config.remoteNameOnly
            if isActive {
                try? await fileProviderBridge.removeDomain(identifier: name)
            } else {
                try? await fileProviderBridge.addDomain(identifier: name, displayName: name)
            }
            await fileProviderBridge.refreshDomains()
        }
    }

    private func removeMount(config: MountConfig) async {
        if config.backend == .fileProvider {
            try? await fileProviderBridge.removeDomain(identifier: config.remoteNameOnly)
            await fileProviderBridge.refreshDomains()
        } else if mountManager.activeMounts.contains(where: { $0.mountPoint == config.mountPoint }) {
            try? await mountManager.unmount(mountPoint: config.mountPoint)
        }
        configStore.removeConfig(id: config.id)
    }
}
