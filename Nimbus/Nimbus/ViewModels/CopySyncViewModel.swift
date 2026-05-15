import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class CopySyncViewModel {
    private(set) var remoteNames: [String] = []
    private(set) var error: NimbusError?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        do {
            remoteNames = try await client.listRemotes()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    /// Clears the most-recent error so the inline EmptyState banner can be
    /// dismissed without re-issuing the failing request.
    func clearError() {
        error = nil
    }

    /// Starts a copy/sync. Owns its own error state so the view can render a
    /// single VM-driven banner (cleared via `clearError()`) instead of
    /// juggling a separate `@State` error string.
    func startOperation(
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        store: TransferStore
    ) async {
        error = nil
        do {
            let jobId: Int
            switch operation {
            case .copy:
                jobId = try await client.copy(srcFs: srcFs, dstFs: dstFs)
            case .sync:
                jobId = try await client.sync(srcFs: srcFs, dstFs: dstFs)
            case .move:
                // The Copy/Sync screen UI doesn't expose move; it's used by
                // `DragDropCoordinator` for within-remote drag-and-drop. Guard
                // against future misuse rather than silently mapping to copy.
                assertionFailure("CopySyncViewModel does not support .move")
                return
            }
            store.addTransfer(jobId: jobId, operation: operation, srcFs: srcFs, dstFs: dstFs)
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
