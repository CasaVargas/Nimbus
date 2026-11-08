import SwiftUI
import RcloneKit
import os

/// Detail pane for one remote: header, capacity gauge, tabs, and the
/// transfer drawer. Owns nothing persistent; the browser, transfers, and
/// mounts views it hosts keep their own state.
struct VolumeView: View {
    let remote: Remote
    /// Every configured cloud, so an alias can show the service it points at.
    var allRemotes: [Remote] = []
    var browseTarget: BrowseTarget?
    /// (source remote, source path) for the Copy & Sync tool.
    var onSync: (String, String) -> Void

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService
    @Environment(ProviderDirectory.self) private var providers
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @Environment(MountConfigStore.self) private var mountConfigs
    @Environment(AppSettings.self) private var settings

    @State private var tab: VolumeTab = Self.initialTab
    @State private var showEdit = false
    @State private var browserModel: BrowserViewModel?
    @State private var quickLookHost = QuickLookHost()
    @State private var integrationError: NimbusError?

    private static let quotaRefreshInterval: Duration = .seconds(300)

    /// Debug builds honor `-debugInitialVolumeTab <files|transfers|finder|settings>`
    /// so screenshots and UI checks can land on a tab without a click.
    private static var initialTab: VolumeTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "debugInitialVolumeTab"),
           let tab = VolumeTab(rawValue: raw) {
            return tab
        }
        #endif
        return .files
    }

    private var resolvedType: String {
        CloudNaming.resolvedType(of: remote, in: allRemotes)
    }

    private var isInFinder: Bool {
        FinderIntegration.isShown(remote: remote.name, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            VolumeHeader(
                remote: remote,
                badgeType: resolvedType,
                providerName: CloudNaming.providerName(forType: resolvedType, directory: providers),
                quota: statusService.quotas[remote.name],
                status: statusService.statuses[remote.name] ?? .unknown,
                isInFinder: isInFinder,
                onPrimary: { Task { await primaryAction() } },
                onSync: { onSync(remote.name, "") },
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
            if tab == .files {
                ToolbarItem(placement: .primaryAction) {
                    @Bindable var settings = settings
                    Toggle(isOn: $settings.inspectorVisible) {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show or hide the inspector")
                }
            }
        }
        .task(id: remote.name) {
            if browserModel == nil {
                let model = BrowserViewModel(client: daemon.client)
                model.remote = remote.name
                model.path = browseTarget?.remote == remote.name ? (browseTarget?.path ?? "") : ""
                browserModel = model
            }
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
            if let browserModel {
                HStack(spacing: 0) {
                    BrowserView(
                        remoteName: remote.name,
                        initialPath: browserModel.path,
                        browseTarget: browseTarget,
                        showsToolbar: tab == .files,
                        sharedModel: browserModel
                    )
                    if settings.inspectorVisible {
                        Divider()
                        FileInspector(
                            remote: remote.name,
                            model: browserModel,
                            onQuickLook: { items in Task { await quickLook(items) } },
                            onCopy: { file in onSync(remote.name, file.isDir ? file.path : (file.path as NSString).deletingLastPathComponent) }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(DesignSystem.Motion.smooth, value: settings.inspectorVisible)
                .opacity(tab == .files ? 1 : 0)
                .allowsHitTesting(tab == .files)
                .accessibilityHidden(tab != .files)
            }

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

    private func quickLook(_ items: [FileItem]) async {
        guard !items.isEmpty else { return }
        let provider = QuickLookHost.provider(
            forRemote: remote.name,
            bridge: fileProviderBridge,
            client: RcloneClientAdapter(client: daemon.client)
        )
        await quickLookHost.show(items: items, provider: provider, remote: remote.name)
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
