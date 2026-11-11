import Foundation

/// When the working set re-lists folders, and which ones (#76). Pure: the
/// extension persists a `RemoteChangeCadence.State` per cloud and asks
/// `decide` on every working-set pass. See
/// `docs/superpowers/specs/2026-11-11-faster-remote-changes-design.md`.
enum RemoteChangeCadence {
    /// Every known folder is re-listed at least this often.
    static let fullInterval: TimeInterval = 600
    /// First wait before a hot scan, and the wait after a change.
    static let baseHotInterval: TimeInterval = 30
    /// Longest wait between hot scans that keep finding nothing.
    static let maxHotInterval: TimeInterval = 300
    /// A folder stops being hot this long after its last activity.
    static let hotLifetime: TimeInterval = 30 * 60
    /// Most hot folders scanned per cloud per pass.
    static let maxHotFolders = 50

    enum Scope: Equatable, Sendable {
        case full
        case hot([String])
        case none
    }

    struct State: Codable, Equatable, Sendable {
        /// Container identifier → last activity (seconds since 1970).
        var activity: [String: TimeInterval] = [:]
        var lastFullScan: TimeInterval?
        var lastScan: TimeInterval?
        var hotInterval: TimeInterval = RemoteChangeCadence.baseHotInterval

        /// Records activity in `container`. Activity after the last scan
        /// resets the wait, so a folder the user is in gets checked soon.
        mutating func touch(_ container: String, at now: Date) {
            let t = now.timeIntervalSince1970
            activity[container] = t
            if let lastScan, t > lastScan { hotInterval = RemoteChangeCadence.baseHotInterval }
        }

        /// Drops activity older than `hotLifetime`.
        mutating func expire(at now: Date) {
            let cutoff = now.timeIntervalSince1970 - RemoteChangeCadence.hotLifetime
            activity = activity.filter { $0.value >= cutoff }
        }

        /// Hot folders, pinned first, then most recent, capped. `isKnown`
        /// keeps only folders with a listing snapshot.
        func hotFolders(at now: Date, pinned: Set<String>, isKnown: (String) -> Bool) -> [String] {
            let cutoff = now.timeIntervalSince1970 - RemoteChangeCadence.hotLifetime
            let recent = activity
                .filter { $0.value >= cutoff && !pinned.contains($0.key) }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map(\.key)
            var seen = Set<String>()
            return (pinned.sorted() + recent)
                .filter { isKnown($0) && seen.insert($0).inserted }
                .prefix(RemoteChangeCadence.maxHotFolders)
                .map { $0 }
        }

        /// Records a finished scan. Changes reset the wait; a quiet hot
        /// scan doubles it up to `maxHotInterval`.
        mutating func recordScan(_ scope: Scope, foundChanges: Bool, at now: Date) {
            let t = now.timeIntervalSince1970
            switch scope {
            case .none: return
            case .full: lastFullScan = t
            case .hot: break
            }
            if foundChanges {
                hotInterval = RemoteChangeCadence.baseHotInterval
            } else if case .hot = scope {
                hotInterval = min(hotInterval * 2, RemoteChangeCadence.maxHotInterval)
            }
            lastScan = t
        }
    }

    /// The scope of this pass. `fullRequestedAt` is the app's last request
    /// (`FullScanRequest`).
    static func decide(
        state: State,
        hotFolders: [String],
        fullRequestedAt: Date?,
        now: Date
    ) -> Scope {
        let t = now.timeIntervalSince1970
        guard let lastFull = state.lastFullScan else { return .full }
        if t - lastFull >= fullInterval { return .full }
        if let requested = fullRequestedAt?.timeIntervalSince1970, requested > lastFull { return .full }
        guard !hotFolders.isEmpty else { return .none }
        let due = (state.lastScan ?? 0) + state.hotInterval
        return t >= due ? .hot(hotFolders) : .none
    }

    /// Folders to treat as pinned-hot for a set of pinned identifiers: each
    /// pinned item (a folder, if it has a snapshot) and its parent.
    static func pinnedContainers(_ pins: Set<String>, rootKey: String) -> Set<String> {
        var result = Set<String>()
        for pin in pins {
            result.insert(pin)
            result.insert(PinPolicy.parentIdentifier(of: pin) ?? rootKey)
        }
        return result
    }
}

/// The app's "re-list everything on the next pass" request, a timestamp
/// file next to the cloud's snapshots. The app writes it before signalling
/// the working set (refresh, ⌘R); the extension compares it with its last
/// full scan.
enum FullScanRequest {
    static func url(remote: String, base: URL? = AppGroup.containerURL) -> URL? {
        base?
            .appendingPathComponent("FileProviderSync", isDirectory: true)
            .appendingPathComponent(remote, isDirectory: true)
            .appendingPathComponent("full-scan-requested", isDirectory: false)
    }

    static func request(remote: String, at now: Date = Date(), base: URL? = AppGroup.containerURL) {
        guard let url = url(remote: remote, base: base) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(now.timeIntervalSince1970).write(to: url, atomically: true, encoding: .utf8)
    }

    static func requestedAt(remote: String, base: URL? = AppGroup.containerURL) -> Date? {
        guard let url = url(remote: remote, base: base),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension RemoteChangeWalk {
    /// Visits a flat list of folders, at most `width` at a time, in order.
    static func visitAll<Payload: Sendable>(
        _ containers: [String],
        width: Int = 4,
        visit: @escaping @Sendable (String) async -> RemoteChangeVisit<Payload>?
    ) async -> [RemoteChangeVisit<Payload>] {
        let width = max(width, 1)
        var results: [RemoteChangeVisit<Payload>] = []
        for start in stride(from: 0, to: containers.count, by: width) {
            let chunk = Array(containers[start..<min(start + width, containers.count)])
            let visits = await withTaskGroup(of: (Int, RemoteChangeVisit<Payload>?).self) { group in
                for (offset, container) in chunk.enumerated() {
                    group.addTask { (offset, await visit(container)) }
                }
                var collected = [RemoteChangeVisit<Payload>?](repeating: nil, count: chunk.count)
                for await (offset, result) in group { collected[offset] = result }
                return collected
            }
            results.append(contentsOf: visits.compactMap { $0 })
        }
        return results
    }
}
