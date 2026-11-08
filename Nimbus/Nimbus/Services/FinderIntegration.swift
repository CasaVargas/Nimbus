import AppKit
import Foundation

/// The one place that flips a remote's File Provider presence. Intent
/// (`AppSettings.disabledFileProviderDomains`) changes first so the UI moves
/// once and immediately; `NSFileProviderManager` registration is eventually
/// consistent and is reconciled in the background by the domain sync. If the
/// registration call throws, intent is rolled back so switches reflect reality.
@MainActor
enum FinderIntegration {
    static func show(remote name: String, settings: AppSettings, bridge: FileProviderBridge) async throws {
        settings.disabledFileProviderDomains.remove(name)
        do {
            try await bridge.addDomain(identifier: name, displayName: name)
        } catch {
            settings.disabledFileProviderDomains.insert(name)
            throw error
        }
        await bridge.refreshDomains()
    }

    static func hide(remote name: String, settings: AppSettings, bridge: FileProviderBridge) async throws {
        settings.disabledFileProviderDomains.insert(name)
        do {
            try await bridge.removeDomain(identifier: name)
        } catch {
            settings.disabledFileProviderDomains.remove(name)
            throw error
        }
        await bridge.refreshDomains()
    }

    /// Whether the user currently wants this remote in Finder. Driven by
    /// intent, not the live domain list, for the reasons above.
    static func isShown(remote name: String, settings: AppSettings) -> Bool {
        !settings.disabledFileProviderDomains.contains(name)
    }

    /// The Finder tab lists mount configurations, so showing a remote in
    /// Finder from the header also records a File Provider configuration
    /// for it (once), the same record `AddMountSheet` would have written.
    static func ensureConfig(remote name: String, store: MountConfigStore, settings: AppSettings) {
        let remoteWithColon = "\(name):"
        let exists = store.configs.contains { $0.remote == remoteWithColon && $0.backend == .fileProvider }
        guard !exists else { return }
        store.addConfig(MountConfig(
            remote: remoteWithColon,
            mountPoint: "",
            vfsMode: settings.newMountAccess == .readOnly ? .readOnly : .readWrite,
            autoMount: settings.newMountAutoMount,
            backend: .fileProvider
        ))
    }

    static func open(remote name: String, bridge: FileProviderBridge) async {
        if let url = await bridge.urlForItem(remote: name, path: "") {
            NSWorkspace.shared.open(url)
        }
    }
}
