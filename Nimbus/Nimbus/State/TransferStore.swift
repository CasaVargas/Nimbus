import Foundation
import Observation
import RcloneKit
import os

enum TransferOperation: String {
    case copy
    case sync
    case move
}

enum TransferStatus {
    case active
    case completed
    case failed(String)
    case cancelled
}

extension TransferStatus {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

/// Distinguishes how a transfer was initiated so the UI can group / label
/// activity sensibly (manual single-file copies, cross-remote drops from
/// the browser, or batched copy/sync jobs from the Copy/Sync screen).
enum TransferOrigin: String, Sendable {
    case manual
    case crossRemoteDrop
    case copySyncJob
}

struct Transfer: Identifiable {
    let id: Int
    let operation: TransferOperation
    let srcFs: String
    let dstFs: String
    let startedAt: Date
    var completedAt: Date?
    var status: TransferStatus
    let origin: TransferOrigin
    let nimbusUUID: UUID
    var progress: Double = 0.0
}

@Observable
@MainActor
final class TransferStore {
    private(set) var transfers: [Transfer] = []
    private var pollingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "transfer-store")

    var activeTransfers: [Transfer] {
        transfers.filter {
            if case .active = $0.status { return true }
            return false
        }
    }

    var completedTransfers: [Transfer] {
        transfers.filter {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
    }

    func addTransfer(
        jobId: Int,
        operation: TransferOperation,
        srcFs: String,
        dstFs: String,
        origin: TransferOrigin = .manual,
        nimbusUUID: UUID = UUID()
    ) {
        let transfer = Transfer(
            id: jobId,
            operation: operation,
            srcFs: srcFs,
            dstFs: dstFs,
            startedAt: Date(),
            status: .active,
            origin: origin,
            nimbusUUID: nimbusUUID
        )
        transfers.append(transfer)
    }

    /// Updates the progress for an in-flight transfer. Clamped to `0...1`.
    func setProgress(_ progress: Double, forJobId id: Int) {
        guard let idx = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[idx].progress = max(0, min(1, progress))
    }

    func completeTransfer(jobId: Int) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .completed
            transfers[index].completedAt = Date()
        }
    }

    func failTransfer(jobId: Int, error: String) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .failed(error)
            transfers[index].completedAt = Date()
        }
    }

    func cancelTransfer(jobId: Int) {
        if let index = transfers.firstIndex(where: { $0.id == jobId }) {
            transfers[index].status = .cancelled
            transfers[index].completedAt = Date()
        }
    }

    func clearCompleted() {
        transfers.removeAll {
            switch $0.status {
            case .completed, .failed, .cancelled: return true
            case .active: return false
            }
        }
    }

    func startPolling(client: RcloneClient) {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.pollActiveJobs(client: client)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollActiveJobs(client: RcloneClient) async {
        for transfer in activeTransfers {
            do {
                let job = try await client.jobStatus(id: transfer.id)
                if job.finished {
                    if job.success {
                        completeTransfer(jobId: transfer.id)
                    } else {
                        failTransfer(jobId: transfer.id, error: job.error)
                    }
                }
            } catch {
                // Job may have been cleaned up by rclone — expected for old jobs.
                // Transient errors will cause retries on the next poll cycle.
                logger.debug("Job \(transfer.id) status poll failed (may be cleaned up): \(error)")
            }
        }
    }
}
