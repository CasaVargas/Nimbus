import Foundation

/// Signals every File Provider working set every 30 seconds while Nimbus
/// runs (#76). A signal costs no network: the extension re-lists only hot
/// folders, and only when their backoff is up (`RemoteChangeCadence`).
/// Full re-lists stay on `CloudMonitor`'s refresh.
@MainActor
final class RemoteChangeTicker {
    static let interval: Duration = .seconds(30)

    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let signal: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    init(interval: Duration = RemoteChangeTicker.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         signal: @escaping @Sendable () async -> Void = { await FileProviderBridge.signalWorkingSets(fullScan: false) }) {
        self.interval = interval
        self.sleep = sleep
        self.signal = signal
    }

    var isRunning: Bool { task != nil }

    /// Starts the tick once; later calls are no-ops.
    func start() {
        guard task == nil else { return }
        let interval = self.interval
        let signal = self.signal
        let sleep = self.sleep
        task = Task {
            while !Task.isCancelled {
                try? await sleep(interval)
                guard !Task.isCancelled else { return }
                await signal()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
