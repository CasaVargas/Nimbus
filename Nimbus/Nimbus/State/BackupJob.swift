import CryptoKit
import Foundation

/// A saved backup: what to copy where, how, and when. Persisted in
/// `backups-v1.json` by `BackupStore`. See
/// `docs/superpowers/specs/2026-11-08-backups-design.md`.
struct BackupJob: Codable, Identifiable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable {
        /// `sync/sync`: the destination matches the source.
        case mirror
        /// `sync/copy`: new and changed files only; nothing is removed.
        case addOnly
    }

    struct Versions: Codable, Hashable, Sendable {
        enum Location: Hashable, Sendable {
            case insideDestination
            case custom(TransferEndpoint)
        }

        enum Keep: String, Codable, Sendable {
            case forever, days30, days90, year1
        }

        var enabled: Bool
        var location: Location
        var keep: Keep
    }

    let id: UUID
    var name: String
    var source: TransferEndpoint
    var destination: TransferEndpoint
    var mode: Mode
    var excludes: [String]
    var versions: Versions
    /// Mirror only; nil means no limit.
    var removalLimit: Int?
    var schedule: BackupSchedule
    var isPaused: Bool
    var approvedFingerprint: String?
    /// Anchors the first scheduled run. Not part of the fingerprint.
    var approvedAt: Date?
    let createdAt: Date
    var lastRun: BackupRunSummary?
}

extension BackupJob {
    static let versionsFolderName = ".nimbus-versions"
    static let macJunkExcludes = [".DS_Store", "._*", ".Trash/**", ".Spotlight-V100/**"]

    static func new(source: TransferEndpoint, destination: TransferEndpoint, now: Date) -> BackupJob {
        BackupJob(
            id: UUID(),
            name: "\(source.displayName) to \(destination.cloudName ?? destination.displayName)",
            source: source,
            destination: destination,
            mode: .mirror,
            excludes: macJunkExcludes,
            versions: Versions(enabled: true, location: .insideDestination, keep: .forever),
            removalLimit: 100,
            schedule: .manual,
            isPaused: false,
            approvedFingerprint: nil,
            approvedAt: nil,
            createdAt: now,
            lastRun: nil
        )
    }

    /// SHA-256 over everything that decides what a run does. Name, schedule,
    /// pause and version retention are deliberately left out: changing them
    /// doesn't change which files a run copies or removes.
    var fingerprint: String {
        let input = FingerprintInput(
            source: source,
            destination: destination,
            mode: mode,
            excludes: excludes,
            versionsEnabled: versions.enabled,
            versionsLocation: versions.location,
            removalLimit: removalLimit
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(input)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A job may run only after its current shape was previewed and approved.
    var isApproved: Bool { approvedFingerprint == fingerprint }

    /// The last run stopped at the removal limit, after removing up to the
    /// limit, and nobody has previewed and approved the job since. Scheduled
    /// runs wait for that approval, so they never keep removing files the
    /// user hasn't seen.
    var isStoppedAtRemovalLimit: Bool {
        guard let lastRun, lastRun.outcome == .limitHit else { return false }
        return (approvedAt ?? .distantPast) < lastRun.startedAt
    }

    /// Where replaced and removed files go, or nil when versions are off.
    var versionsEndpoint: TransferEndpoint? {
        guard versions.enabled else { return nil }
        switch versions.location {
        case .insideDestination: return destination.appending(Self.versionsFolderName)
        case .custom(let endpoint): return endpoint
        }
    }

    private struct FingerprintInput: Encodable {
        let source: TransferEndpoint
        let destination: TransferEndpoint
        let mode: Mode
        let excludes: [String]
        let versionsEnabled: Bool
        let versionsLocation: Versions.Location
        let removalLimit: Int?
    }
}

extension BackupJob.Versions.Location: Codable {
    private enum CodingKeys: String, CodingKey { case kind, endpoint }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "custom": self = .custom(try container.decode(TransferEndpoint.self, forKey: .endpoint))
        default: self = .insideDestination
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insideDestination:
            try container.encode("insideDestination", forKey: .kind)
        case .custom(let endpoint):
            try container.encode("custom", forKey: .kind)
            try container.encode(endpoint, forKey: .endpoint)
        }
    }
}

// MARK: - Schedule

enum BackupSchedule: Hashable, Sendable {
    case manual
    case hourly
    case daily(hour: Int, minute: Int)
    /// `weekday` uses Calendar numbering: 1 = Sunday.
    case weekly(weekday: Int, hour: Int, minute: Int)

    /// The first slot strictly after `date`, or nil for `.manual`. A time
    /// that doesn't exist (spring forward) moves to the next existing time;
    /// a time that happens twice (fall back) runs on its first occurrence.
    func nextRun(after date: Date, calendar: Calendar) -> Date? {
        let components: DateComponents
        switch self {
        case .manual: return nil
        case .hourly: components = DateComponents(minute: 0, second: 0)
        case .daily(let hour, let minute): components = DateComponents(hour: hour, minute: minute, second: 0)
        case .weekly(let weekday, let hour, let minute):
            components = DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday)
        }
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

extension BackupSchedule: Codable {
    private enum CodingKeys: String, CodingKey { case kind, hour, minute, weekday }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "hourly":
            self = .hourly
        case "daily":
            self = .daily(hour: try container.decode(Int.self, forKey: .hour),
                          minute: try container.decode(Int.self, forKey: .minute))
        case "weekly":
            self = .weekly(weekday: try container.decode(Int.self, forKey: .weekday),
                           hour: try container.decode(Int.self, forKey: .hour),
                           minute: try container.decode(Int.self, forKey: .minute))
        default:
            self = .manual
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try container.encode("manual", forKey: .kind)
        case .hourly:
            try container.encode("hourly", forKey: .kind)
        case .daily(let hour, let minute):
            try container.encode("daily", forKey: .kind)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .weekly(let weekday, let hour, let minute):
            try container.encode("weekly", forKey: .kind)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        }
    }
}

// MARK: - Run summary

struct BackupRunSummary: Codable, Hashable, Sendable {
    enum Trigger: String, Codable, Sendable { case manual, scheduled, catchUp }

    enum Outcome: Hashable, Sendable {
        case completed
        case failed(String)
        case cancelled
        /// rclone stopped the run at the job's removal limit (`MaxDelete`).
        case limitHit
    }

    let startedAt: Date
    let finishedAt: Date
    let trigger: Trigger
    var outcome: Outcome
    let copied: Int
    let replaced: Int
    let removed: Int
    let errors: Int
    let bytes: Int64
    /// The job's removal limit when the run started; names the number in the
    /// "stopped" notification. Absent in summaries saved before it existed.
    var removalLimit: Int? = nil
    /// Mirror with versions: replaced and removed files were moved into the
    /// versions folder, not deleted. Optional so summaries saved by earlier
    /// builds (no key) still decode; nil reads as false.
    var movesToVersions: Bool? = nil
}

extension BackupRunSummary.Outcome: Codable {
    private enum CodingKeys: String, CodingKey { case failed }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            switch raw {
            case "completed": self = .completed
            case "cancelled": self = .cancelled
            case "limitHit": self = .limitHit
            default: self = .failed(raw)
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .failed(try container.decode(String.self, forKey: .failed))
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .completed:
            var single = encoder.singleValueContainer()
            try single.encode("completed")
        case .cancelled:
            var single = encoder.singleValueContainer()
            try single.encode("cancelled")
        case .limitHit:
            var single = encoder.singleValueContainer()
            try single.encode("limitHit")
        case .failed(let message):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .failed)
        }
    }
}
