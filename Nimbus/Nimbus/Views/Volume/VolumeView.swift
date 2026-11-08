import SwiftUI
import RcloneKit
import os

/// Detail pane for one remote: header, capacity gauge, tabs, and the
/// transfer drawer. Owns nothing persistent; the browser, transfers, and
/// mounts views it hosts keep their own state.
struct VolumeView: View {
    let remote: Remote
    var browseTarget: BrowseTarget?
    var onSync: (String) -> Void

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(ProviderDirectory.self) private var providers
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @Environment(MountConfigStore.self) private var mountConfigs
    @Environment(AppSettings.self) private var settings

    @State private var tab: VolumeTab = .files
    @State private var showEdit = false
    @State private var integrationError: NimbusError?

    private static let quotaRefreshInterval: Duration = .seconds(300)

    private var isInFinder: Bool {
        FinderIntegration.isShown(remote: remote.name, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            VolumeHeader(
                remote: remote,
                providerName: providers.displayName(forType: remote.type),
                quota: statusService.quotas[remote.name],
                status: statusService.statuses[remote.name] ?? .unknown,
                isInFinder: isInFinder,
                onPrimary: { Task { await primaryAction() } },
                onSync: { onSync(remote.name) },
                onEdit: { showEdit = true }
            )
            if let quota = statusService.quotas[remote.name], quota.fraction != nil {
                StorageGauge(quota: quota)
            }
            VolumeTabBar(selection: $tab)
            Divider()
            tabContent
            TransferDrawer(onShowAll: { tab = .transfers })
        }
        .background(DesignSystem.Color.semantic.surface)
        .navigationTitle(remote.name)
        .toolbar {
            ToolbarItem(placement: .status) {
                TransferPillView(onTap: { tab = .transfers })
            }
        }
        .task(id: remote.name) {
            if statusService.quotas[remote.name] == nil {
                await statusService.refreshQuota(remote.name)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.quotaRefreshInterval)
                guard !Task.isCancelled else { return }
                await statusService.refreshQuota(remote.name)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditRemoteSheet(client: daemon.client, remote: remote, onDismiss: {
                NotificationCenter.default.post(name: .nimbusRemotesChanged, object: nil)
            })
        }
        .alert(
            "Couldn't update Finder",
            isPresented: Binding(get: { integrationError != nil }, set: { if !$0 { integrationError = nil } }),
            presenting: integrationError
        ) { _ in
            Button("OK", role: .cancel) { integrationError = nil }
        } message: { error in
            Text(verbatim: error.message)
        }
    }

    /// The Files tab stays mounted (hidden, not removed) while another tab
    /// shows, so switching tabs never drops the listing, selection, or
    /// navigation history.
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            BrowserView(
                remoteName: remote.name,
                initialPath: browseTarget?.remote == remote.name ? (browseTarget?.path ?? "") : "",
                browseTarget: browseTarget,
                showsToolbar: tab == .files
            )
            .opacity(tab == .files ? 1 : 0)
            .allowsHitTesting(tab == .files)
            .accessibilityHidden(tab != .files)

            switch tab {
            case .files:
                EmptyView()
            case .transfers:
                TransfersView(remoteFilter: remote.name)
                    .background(DesignSystem.Color.semantic.surface)
            case .finder:
                MountsView(remoteFilter: remote.name)
                    .background(DesignSystem.Color.semantic.surface)
            case .settings:
                VolumeSettingsTab(remote: remote, onEdit: { showEdit = true })
                    .background(DesignSystem.Color.semantic.surface)
            }
        }
    }

    private func primaryAction() async {
        if isInFinder {
            await FinderIntegration.open(remote: remote.name, bridge: fileProviderBridge)
            return
        }
        do {
            try await FinderIntegration.show(remote: remote.name, settings: settings, bridge: fileProviderBridge)
            FinderIntegration.ensureConfig(remote: remote.name, store: mountConfigs, settings: settings)
        } catch {
            integrationError = NimbusError.classify(error)
        }
    }
}
