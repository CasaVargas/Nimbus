import Foundation
import RcloneKit

/// Deletes a backup's versions folders older than its Keep for setting.
///
/// Each run moves replaced and removed files into `<versions folder>/<run
/// stamp>/`. Pruning lists the versions folder and purges the direct
/// children whose **name** is a run stamp older than the cut-off. File dates
/// are never used: `--backup-dir` keeps each file's original modification
/// time, so a two-year-old file removed today would go at once.
///
/// Purging is recursive and permanent, so every path handed to `purge` comes
/// from `purgeTarget`, which only ever returns `<versions folder>/<stamp>`.
enum VersionsPruner {
    /// An rclone `fs` and `remote` pair: the root of a cloud (`"b2:"`) or of
    /// this Mac (`"/"`), and a path below it.
    struct Location: Equatable, Sendable {
        let fs: String
        let remote: String
    }

    enum Outcome: Equatable, Sendable {
        /// Nothing to do: versions off, kept forever, or no safe folder.
        case skipped
        /// The stamp folders that were purged (possibly none).
        case pruned([String])
        case failed(String)
        /// The versions folder doesn't exist yet: no run has kept anything.
        case noVersionsYet
        /// The job changed while pruning (deleted, versions off, another
        /// folder, a longer Keep for): stopped after purging these.
        case stopped([String])
    }

    /// Asked on the main actor before each purge, with the stamp about to
    /// go: false stops the prune. The runner checks the job as it is now.
    typealias MayPurge = @MainActor @Sendable (String) -> Bool

    /// The Keep for that applies to `job`'s versions folder. Stamp folders
    /// don't say which job made them, so when other saved jobs (versions on)
    /// use the same folder, the longest Keep among them wins, and any
    /// Forever means nothing is pruned.
    static func effectiveKeep(for job: BackupJob, among jobs: [BackupJob]) -> BackupJob.Versions.Keep {
        guard let folder = versionsFolder(of: job) else { return job.versions.keep }
        let sharers = jobs.filter { $0.id != job.id && versionsFolder(of: $0) == folder }
        return ([job] + sharers).map(\.versions.keep).max { $0.retention < $1.retention } ?? job.versions.keep
    }

    /// The names in `names` that are run stamps past the Keep for cut-off
    /// (see `isPastCutOff`), in listing order, less the newest stamp. Names
    /// that aren't stamps are ignored; `.forever` prunes nothing.
    static func foldersToPrune(names: [String], keep: BackupJob.Versions.Keep, now: Date, timeZone: TimeZone) -> [String] {
        // The newest stamp folder stays whatever its age, so a clock set
        // forward by mistake can't empty the versions folder. Found by date,
        // not by where the listing puts it.
        let newest = names
            .compactMap { name in BackupRequest.date(fromStamp: name, timeZone: timeZone).map { (name, $0) } }
            .max { $0.1 < $1.1 }?.0
        return names.filter { $0 != newest && isPastCutOff($0, keep: keep, now: now, timeZone: timeZone) }
    }

    /// Days added to every Keep for before anything goes: a time-zone change
    /// can make a stamp look up to about a day older than it is, and a purge
    /// can't be undone.
    static let graceDays = 1

    /// Whether `name` is a run stamp strictly older than `keep`'s cut-off:
    /// its days plus `graceDays` before `now`, on the calendar in `timeZone`.
    static func isPastCutOff(_ name: String, keep: BackupJob.Versions.Keep, now: Date, timeZone: TimeZone) -> Bool {
        guard let days = keep.days else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let cutOff = calendar.date(byAdding: .day, value: -(days + graceDays), to: now),
              let date = BackupRequest.date(fromStamp: name, timeZone: timeZone) else { return false }
        return date < cutOff
    }

    /// The one path pruning may purge: `<job's versions folder>/<stamp>`.
    /// Nil unless `stamp` is exactly a run stamp and the versions folder is
    /// a real folder below a cloud's or this Mac's root.
    static func purgeTarget(job: BackupJob, stamp: String) -> Location? {
        // Shape only; any fixed zone works, and UTC has no skipped hours.
        guard BackupRequest.date(fromStamp: stamp, timeZone: .gmt) != nil,
              let folder = versionsFolder(of: job) else { return nil }
        return Location(fs: folder.fs, remote: folder.remote + "/" + stamp)
    }

    /// The job's versions folder, or nil when versions are off or the folder
    /// is a cloud's or this Mac's root (or a path that isn't plainly below one).
    static func versionsFolder(of job: BackupJob) -> Location? {
        guard let endpoint = job.versionsEndpoint else { return nil }
        switch endpoint {
        case .cloud(let remote, let path):
            guard !remote.isEmpty, !remote.contains(":"), !remote.contains("/"),
                  let relative = relativePath(path) else { return nil }
            return Location(fs: "\(remote):", remote: relative)
        case .local(let path):
            guard path.hasPrefix("/"), let relative = relativePath(path) else { return nil }
            return Location(fs: "/", remote: relative)
        }
    }

    /// Lists the job's versions folder and purges the stamp folders past
    /// `keep` (the job's own Keep for when nil; the runner passes
    /// `effectiveKeep`). Before each purge it asks `mayPurge` and stops when
    /// that says no, so a prune never outlives a change to the job. Stops at
    /// the first failure; never throws.
    static func prune(job: BackupJob, keep: BackupJob.Versions.Keep? = nil, client: any BackupRcloneClient,
                      now: Date, timeZone: TimeZone,
                      mayPurge: @escaping MayPurge = { _ in true }) async -> Outcome {
        let keep = keep ?? job.versions.keep
        guard job.versions.enabled, keep != .forever,
              let folder = versionsFolder(of: job) else { return .skipped }
        let listing: [FileItem]
        do {
            listing = try await client.listFiles(fs: folder.fs, remote: folder.remote)
        } catch {
            let message = NimbusError.classify(error).message
            if message.lowercased().contains("directory not found") { return .noVersionsYet }
            return .failed(message)
        }
        let names = listing.filter(\.isDir).map(\.name)
        var pruned: [String] = []
        for name in foldersToPrune(names: names, keep: keep, now: now, timeZone: timeZone) {
            guard let target = purgeTarget(job: job, stamp: name) else { continue }
            // Nothing suspends between this answer and the purge request
            // but the hop back off the main actor.
            guard await mayPurge(name) else { return .stopped(pruned) }
            do {
                try await client.purge(fs: target.fs, remote: target.remote)
            } catch {
                return .failed(NimbusError.classify(error).message)
            }
            pruned.append(name)
        }
        return .pruned(pruned)
    }

    /// `path` without leading or trailing slashes, or nil when that leaves
    /// nothing or it has an empty, `.` or `..` component.
    private static func relativePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !trimmed.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return trimmed
    }
}

extension BackupJob.Versions.Keep {
    /// Orders Keep values from shortest to longest; forever is longest.
    fileprivate var retention: Int { days ?? .max }

    /// Days versions are kept; nil for forever.
    var days: Int? {
        switch self {
        case .forever: nil
        case .days30: 30
        case .days90: 90
        case .year1: 365
        }
    }
}

/// What Show Versions does for a job: open the versions folder in the
/// cloud's browser; on this Mac open it in Finder (it's hidden, so selecting
/// it might show nothing), or reveal the destination before it exists; or
/// nothing (versions off).
enum VersionsReveal: Equatable {
    case browse(cloud: String, path: String)
    case open(URL)
    case reveal(URL)
    case unavailable

    static func target(for job: BackupJob, versionsFolderExists: Bool) -> VersionsReveal {
        guard let endpoint = job.versionsEndpoint else { return .unavailable }
        switch endpoint {
        case .cloud(let remote, let path):
            guard !remote.isEmpty else { return .unavailable }
            return .browse(cloud: remote, path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        case .local(let path):
            guard path.hasPrefix("/") else { return .unavailable }
            if versionsFolderExists { return .open(URL(fileURLWithPath: path, isDirectory: true)) }
            guard case .local(let destination) = job.destination else { return .unavailable }
            return .reveal(URL(fileURLWithPath: destination, isDirectory: true))
        }
    }
}
