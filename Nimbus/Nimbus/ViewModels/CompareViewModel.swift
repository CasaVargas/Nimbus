import Foundation
import Observation
import RcloneKit

/// The rclone calls Compare needs. `RcloneClient` provides them; tests use a
/// scripted mock.
protocol CompareRcloneClient: Sendable {
    func listRemotes() async throws -> [String]
    func startCheck(_ request: CheckRequest) async throws -> Int
    func checkStatus(id: Int) async throws -> CheckJobStatus
    func getStats(group: String?) async throws -> StatsResponse
    func stopJob(id: Int) async throws
}

extension RcloneClient: CompareRcloneClient {}

/// Two folders' files, grouped. Paths are relative to each folder's root.
struct CompareResult: Equatable, Sendable {
    var same: [String] = []
    var differ: [String] = []
    var onlyInA: [String] = []
    var onlyInB: [String] = []
    var errors: [String] = []
    /// Content wasn't compared: the two places share no hash type.
    var comparedWithoutHash = false

    var matches: Bool { differ.isEmpty && onlyInA.isEmpty && onlyInB.isEmpty && errors.isEmpty }
    var total: Int { same.count + differ.count + onlyInA.count + onlyInB.count + errors.count }

    /// Parses rclone's `combined` lines (`<sign> <path>`). A is rclone's
    /// src, B its dst: `+` is missing on dst, so only in A. Unknown lines
    /// are skipped. Each group is sorted for display.
    init(combined: [String], comparedWithoutHash: Bool = false) {
        self.comparedWithoutHash = comparedWithoutHash
        for line in combined {
            guard line.count >= 3, line.dropFirst().first == " " else { continue }
            let path = String(line.dropFirst(2))
            switch line.first {
            case "=": same.append(path)
            case "*": differ.append(path)
            case "+": onlyInA.append(path)
            case "-": onlyInB.append(path)
            case "!": errors.append(path)
            default: continue
            }
        }
        let order: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        same.sort(by: order)
        differ.sort(by: order)
        onlyInA.sort(by: order)
        onlyInB.sort(by: order)
        errors.sort(by: order)
    }

    init() {}
}

/// Compares two folders with rclone's `operations/check`. Read-only: it
/// never copies, syncs or deletes. One compare at a time.
@Observable
@MainActor
final class CompareViewModel {
    enum State: Equatable, Sendable {
        case idle
        case running(checked: Int)
        case finished(CompareResult)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var remoteNames: [String] = []

    @ObservationIgnored private let client: any CompareRcloneClient
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var runningJobID: Int?
    @ObservationIgnored private var stopped = false

    init(client: any CompareRcloneClient, pollInterval: Duration = .milliseconds(250)) {
        self.client = client
        self.pollInterval = pollInterval
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func loadRemotes() async {
        remoteNames = (try? await client.listRemotes()) ?? remoteNames
    }

    /// Clears a result or an error, back to the empty screen.
    func reset() {
        guard !isRunning else { return }
        state = .idle
    }

    func compare(_ a: TransferEndpoint, _ b: TransferEndpoint, method: CheckRequest.Method) async {
        guard !isRunning else { return }
        stopped = false
        state = .running(checked: 0)

        let jobID: Int
        do {
            jobID = try await client.startCheck(CheckRequest(srcFs: a.fs, dstFs: b.fs, method: method))
        } catch {
            state = .failed(Self.friendly(error))
            return
        }
        // Stop was pressed while the start was in flight: stop the job
        // rclone just created (the screen is already idle).
        if stopped {
            try? await client.stopJob(id: jobID)
            return
        }
        runningJobID = jobID
        defer { runningJobID = nil }

        while true {
            if stopped { return }
            if Task.isCancelled { await stop(jobID); return }
            let job: CheckJobStatus
            do {
                job = try await client.checkStatus(id: jobID)
            } catch {
                state = .failed(Self.friendly(error))
                return
            }
            if stopped { return }
            if Task.isCancelled { await stop(jobID); return }
            guard job.finished else {
                let stats = try? await client.getStats(group: job.group)
                if !stopped { state = .running(checked: stats?.checks ?? 0) }
                try? await Task.sleep(for: pollInterval)
                continue
            }
            finish(job, method: method)
            return
        }
    }

    /// Stops a compare that is still running; the screen goes back to idle.
    func stop() async {
        guard isRunning else { return }
        stopped = true
        if let runningJobID { await stop(runningJobID) } else { state = .idle }
    }

    private func stop(_ jobID: Int) async {
        try? await client.stopJob(id: jobID)
        runningJobID = nil
        state = .idle
    }

    private func finish(_ job: CheckJobStatus, method: CheckRequest.Method) {
        // Differences make the *report* unsuccessful, never the job. A
        // failed job is a real failure (missing remote, network).
        guard job.success, let report = job.output else {
            let message = job.error.isEmpty
                ? String(localized: "rclone didn't return a comparison. Try again.")
                : job.error
            state = .failed(BackupErrorText.friendly(message))
            return
        }
        state = .finished(CompareResult(
            combined: report.combined,
            comparedWithoutHash: method == .checksum && report.comparedWithoutHash
        ))
    }

    private static func friendly(_ error: Error) -> String {
        BackupErrorText.friendly(NimbusError.classify(error).message)
    }
}
