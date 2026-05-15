import Foundation
import Observation
import RcloneKit
import os

@Observable
@MainActor
final class TransfersViewModel {
    private(set) var overallStats: StatsResponse?
    private(set) var error: NimbusError?

    private let client: RcloneClient
    private var statsTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "transfers")

    init(client: RcloneClient) {
        self.client = client
    }

    func startStatsPolling() {
        statsTask = Task {
            while !Task.isCancelled {
                await self.fetchStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
    }

    func cancelJob(id: Int) async {
        do {
            try await client.stopJob(id: id)
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private func fetchStats() async {
        do {
            overallStats = try await client.getStats()
        } catch {
            logger.debug("Stats polling error (transient): \(error)")
        }
    }
}
