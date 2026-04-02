import SwiftUI
import RcloneKit

struct MountsView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var configStore
    @Environment(MountManager.self) private var mountManager
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
                AddMountSheet(remoteNames: viewModel?.remoteNames ?? [])
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
                let isActive = mountManager.activeMounts.contains { $0.mountPoint == config.mountPoint }
                MountRow(
                    config: config,
                    isActive: isActive,
                    onToggle: { Task { await toggleMount(config: config, isActive: isActive) } },
                    onRemove: { configStore.removeConfig(id: config.id) }
                )
            }
        }
    }

    private func toggleMount(config: MountConfig, isActive: Bool) async {
        if isActive {
            try? await mountManager.unmount(mountPoint: config.mountPoint)
        } else {
            try? await mountManager.mount(
                remote: config.remote,
                mountPoint: config.mountPoint,
                readOnly: config.vfsMode == .readOnly
            )
        }
    }
}
