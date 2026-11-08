import FileProvider
import os

/// Finder's **Keep Downloaded** / **Allow Removing Download** actions
/// (declared in Info.plist under `NSExtensionFileProviderActions`).
///
/// A pin is recorded in the shared `PinStore`; the extension then signals
/// the affected containers so the system re-reads the items and picks up
/// their new `contentPolicy` (keep-downloaded for pinned items, inherited
/// for their contents). Files are also asked to download right away, so
/// pinning feels immediate even before the system acts on the policy.
enum KeepDownloadedAction {
    static let keep = "app.casavargas.nimbus.keepDownloaded"
    static let allowRemoving = "app.casavargas.nimbus.allowRemovingDownload"

    static func handles(_ identifier: NSFileProviderExtensionActionIdentifier) -> Bool {
        identifier.rawValue == keep || identifier.rawValue == allowRemoving
    }

    static func perform(
        _ action: NSFileProviderExtensionActionIdentifier,
        items: [NSFileProviderItemIdentifier],
        domain: NSFileProviderDomain,
        logger: Logger
    ) async throws {
        let pin = action.rawValue == keep
        let remoteName = domain.identifier.rawValue
        guard let store = PinStore.shared else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
        }
        let identifiers = items.map(\.rawValue)
        try store.setPinned(pin, identifiers: identifiers, domain: remoteName)
        try store.markChanged(identifiers, domain: remoteName)

        guard let manager = NSFileProviderManager(for: domain) else { return }
        // The replicated model only honours signals for the working set; its
        // enumerator reports the changed items from PinStore's change log.
        do {
            try await manager.signalEnumerator(for: .workingSet)
        } catch {
            logger.error("signalEnumerator(workingSet) failed: \(Self.describe(error), privacy: .public)")
        }

        guard pin else { return }
        for item in items where item != .rootContainer {
            do {
                try await manager.requestDownloadForItem(withIdentifier: item)
            } catch {
                logger.info("requestDownload(\(item.rawValue, privacy: .private)) not needed or failed: \(Self.describe(error), privacy: .public)")
            }
        }
    }

    /// Domain and code only: safe to log publicly.
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
