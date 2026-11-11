import Foundation
import Observation
import RcloneKit

/// The rclone call search needs. `RcloneClient` provides it; tests script it.
protocol SearchClient: Sendable {
    func searchFiles(fs: String, query: String) async throws -> [FileItem]
}

extension RcloneClient: SearchClient {
    func searchFiles(fs: String, query: String) async throws -> [FileItem] {
        try await search(fs: fs, query: query)
    }
}

/// One cloud's share of a search.
struct CloudSearchResult: Identifiable, Equatable {
    enum Phase: Equatable {
        case searching
        case done
        case failed(String)
        case timedOut
    }

    let remote: String
    /// Backend type after following aliases, for the section's logo.
    let providerType: String
    var phase: Phase = .searching
    /// Shown items: sorted by name, at most `SearchViewModel.resultCap`.
    var items: [FileItem] = []
    /// Matches before the cap.
    var total = 0

    var id: String { remote }
    var isTruncated: Bool { total > items.count }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.remote == rhs.remote && lhs.phase == rhs.phase && lhs.total == rhs.total
            && lhs.items.map(\.qualifiedRemotePath) == rhs.items.map(\.qualifiedRemotePath)
    }
}

/// Searches every cloud by file name at once. Each cloud runs its own
/// rclone job with its own time limit, and its section fills in as soon as
/// it finishes. Nothing is cached: every search is live.
///
/// Cancellation is structural: `search` runs inside the caller's task (the
/// view's `.task(id:)`), so a new query or leaving search cancels it, and
/// each cloud's rclone job is stopped on the daemon.
@Observable
@MainActor
final class SearchViewModel {
    static let minimumQueryLength = 2
    static let resultCap = 200
    static let debounce: Duration = .milliseconds(400)

    /// The query the current results belong to.
    private(set) var query = ""
    private(set) var clouds: [CloudSearchResult] = []

    var isSearching: Bool { clouds.contains { $0.phase == .searching } }

    private let client: any SearchClient
    private let timeout: Duration
    /// Bumped by every search, so a superseded one can't write its results.
    private var generation = 0

    init(client: any SearchClient, timeout: Duration = .seconds(60)) {
        self.client = client
        self.timeout = timeout
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSearchable(_ raw: String) -> Bool {
        normalized(raw).count >= minimumQueryLength
    }

    /// The clouds worth searching: every remote except an alias that points
    /// into another configured remote, whose files that remote already lists.
    static func searchableRemotes(_ remotes: [Remote]) -> [Remote] {
        let names = Set(remotes.map(\.name))
        return remotes.filter { remote in
            guard remote.type == "alias", let target = remote.config["remote"] else { return true }
            return !names.contains(CloudSummaryBuilder.cloudName(of: target))
        }
    }

    func clear() {
        generation += 1
        query = ""
        clouds = []
    }

    func search(_ raw: String, in remotes: [Remote]) async {
        let query = Self.normalized(raw)
        generation += 1
        let current = generation
        guard query.count >= Self.minimumQueryLength else {
            self.query = ""
            clouds = []
            return
        }

        let targets = Self.searchableRemotes(remotes)
        self.query = query
        clouds = targets.map {
            CloudSearchResult(remote: $0.name, providerType: CloudNaming.resolvedType(of: $0, in: remotes))
        }

        let client = client
        let timeout = timeout
        await withTaskGroup(of: (String, Outcome?).self) { group in
            for remote in targets.map(\.name) {
                group.addTask {
                    (remote, await Self.searchOne(remote: remote, query: query, client: client, timeout: timeout))
                }
            }
            for await (remote, outcome) in group {
                guard let outcome, current == generation, !Task.isCancelled else { continue }
                apply(outcome, to: remote)
            }
        }
    }

    private enum Outcome: Sendable {
        case found([FileItem])
        case failed(String)
        case timedOut
    }

    /// One cloud's search, raced against the time limit. nil means it was
    /// cancelled and has nothing to report.
    nonisolated private static func searchOne(
        remote: String,
        query: String,
        client: any SearchClient,
        timeout: Duration
    ) async -> Outcome? {
        await withTaskGroup(of: Outcome?.self) { race in
            race.addTask {
                do {
                    return .found(try await client.searchFiles(fs: "\(remote):", query: query))
                } catch is CancellationError {
                    return nil
                } catch {
                    return Task.isCancelled ? nil : .failed(NimbusError.classify(error).message)
                }
            }
            race.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return nil
                }
            }
            // The first child to finish decides; the other is cancelled, which
            // stops the rclone job if the clock won.
            let first = await race.next() ?? nil
            race.cancelAll()
            return first
        }
    }

    private func apply(_ outcome: Outcome, to remote: String) {
        guard let index = clouds.firstIndex(where: { $0.remote == remote }) else { return }
        switch outcome {
        case .found(let items):
            let sorted = items
                .map { item in
                    FileItem(
                        path: item.path, name: item.name, size: item.size, mimeType: item.mimeType,
                        modTime: item.modTime, isDir: item.isDir, fileID: item.fileID,
                        qualifiedRemotePath: "\(remote):\(item.path)"
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            clouds[index].items = Array(sorted.prefix(Self.resultCap))
            clouds[index].total = sorted.count
            clouds[index].phase = .done
        case .failed(let message):
            clouds[index].phase = .failed(message)
        case .timedOut:
            clouds[index].phase = .timedOut
        }
    }
}
