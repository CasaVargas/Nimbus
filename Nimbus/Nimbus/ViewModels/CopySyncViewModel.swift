import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class CopySyncViewModel {
    private(set) var remoteNames: [String] = []
    private(set) var error: String?

    private let client: RcloneClient

    init(client: RcloneClient) {
        self.client = client
    }

    func loadRemotes() async {
        do {
            remoteNames = try await client.listRemotes()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startOperation(
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        store: TransferStore
    ) async throws {
        let jobId: Int
        switch operation {
        case .copy:
            jobId = try await client.copy(srcFs: srcFs, dstFs: dstFs)
        case .sync:
            jobId = try await client.sync(srcFs: srcFs, dstFs: dstFs)
        }
        store.addTransfer(jobId: jobId, operation: operation, srcFs: srcFs, dstFs: dstFs)
    }
}
