import FileProvider
import os

/// Records failed uploads for the Finder badge and tells the system.
///
/// A replicated extension is only asked for changes through the working
/// set, so a new failure is appended to `PinStore`'s change log (the log of
/// items whose local-only state changed) and the working set is signalled;
/// `WorkingSetEnumerator` re-fetches the item and reports it, now carrying
/// the failed badge and a new metadata version. An item that doesn't exist
/// on the server (a new file that never arrived) doesn't resolve there and
/// is skipped, so no phantom item appears.
///
/// A cleared failure needs no signal: it is cleared right before the
/// successful create or modify completes, and the item handed back then
/// already carries the cleared state.
enum UploadFailureReporting {
    static func failed(_ error: Error, identifier: String, domain: NSFileProviderDomain, logger: Logger) async {
        guard UploadFailurePolicy.shouldRecord(error), let store = UploadFailureStore.shared else { return }
        let remoteName = domain.identifier.rawValue
        do {
            guard try store.record(identifier, domain: remoteName) else { return }
            try PinStore.shared?.markChanged([identifier], domain: remoteName)
        } catch {
            logger.error("recording a failed upload failed: \(describe(error), privacy: .public)")
            return
        }
        guard let manager = NSFileProviderManager(for: domain) else { return }
        do {
            try await manager.signalEnumerator(for: .workingSet)
        } catch {
            logger.error("signalEnumerator(workingSet) after a failed upload failed: \(describe(error), privacy: .public)")
        }
    }

    static func succeeded(_ identifiers: [String], remoteName: String, logger: Logger) {
        do {
            try UploadFailureStore.shared?.clear(identifiers, domain: remoteName)
        } catch {
            logger.error("clearing a failed upload failed: \(describe(error), privacy: .public)")
        }
    }

    /// Domain and code only: safe to log publicly.
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
