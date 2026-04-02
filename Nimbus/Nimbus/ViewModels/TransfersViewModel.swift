import Foundation
import Observation
import RcloneKit

@Observable
@MainActor
final class TransfersViewModel {
    private(set) var overallStats: StatsResponse?
    private(set) var error: String?

    private let client: RcloneClient
    private var statsTask: Task<Void, Never>?

    init(client: RcloneClient) {
        self.client = client
    }

    func startStatsPolling() {
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchStats()
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
            self.error = error.localizedDescription
        }
    }

    private func fetchStats() async {
        do {
            overallStats = try await client.getStats()
        } catch {
            // Transient — keep polling
        }
    }
}
