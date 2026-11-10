import Foundation
import RcloneKit

/// Everything Home (and, in Phase 2, the menu bar) says about the user's
/// clouds, computed in one place so the two surfaces can never disagree.
/// Pure data: built by `CloudSummaryBuilder` from live services, rendered by
/// views, unit-tested without any of them.
struct CloudSummary: Equatable {
    enum Health: Equatable {
        case ready, busy, checking, needsSignIn, unreachable, failing
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let providerType: String
        let providerName: String
        let health: Health
        /// Plain-language status: "Ready", "Uploading 3 items, 2 min left".
        let sentence: String
        let quota: StorageQuota?
        let isInFinder: Bool
        /// Index into `CloudTint.slots`, assigned in sidebar order.
        let tint: Int
        let lastConnected: Date?
        /// rclone's own message for `.failing` / `.unreachable`, for detail views.
        let errorDetail: String?

        var name: String { id }
    }

    struct Busy: Equatable {
        enum Direction: Equatable { case up, down }
        let progress: Double
        let sentence: String
        let direction: Direction
        /// The cloud whose Transfers tab "Show Transfers" opens.
        let focusCloud: String?
        let eta: TimeInterval?
    }

    enum Overall: Equatable {
        case starting
        case engineDown(String)
        case noClouds
        case allReady
        case busy(Busy)
        case needsAttention(Row)
    }

    enum Suggestion: Equatable, Identifiable {
        case nearlyFull(Row)
        case notInFinder(Row)
        case backup(BackupNote)

        var id: String {
            switch self {
            case .nearlyFull(let row): "full:\(row.id)"
            case .notInFinder(let row): "finder:\(row.id)"
            case .backup(let note): note.dismissKey
            }
        }
    }

    /// One saved backup that needs a look. The sentence is the whole title:
    /// "Documents to B2 hasn't run in 3 days".
    struct BackupNote: Equatable {
        enum Kind: Equatable { case stopped, failed, hasntRun }
        let jobID: UUID
        let kind: Kind
        let sentence: String
        /// Names the run it is about, so dismissing today's failure doesn't
        /// hide the next one.
        let dismissKey: String
    }

    let rows: [Row]
    let overall: Overall
    /// Highest-priority problem, shown as Home's single banner.
    let attention: Row?
    let suggestions: [Suggestion]
    /// Sum of every known `used`.
    let usedBytes: Int64
    /// Sum of `free` over clouds that report a limit; nil when none do, so
    /// Home never invents free space for pay-as-you-go storage.
    let freeBytes: Int64?
    /// Width of the aggregate bar: limits where known, plus usage for clouds
    /// without one, so the bar never overflows.
    let capacityBytes: Int64
}

/// Fixed, distinct system colors for the aggregate bar. Not brand colors:
/// two Google Drive accounts would share one.
enum CloudTint {
    static let count = 8
    static func slot(forIndex index: Int) -> Int { index < count - 1 ? index : count - 1 }
}

enum CloudSummaryBuilder {
    static let nearlyFullThreshold = 0.9
    /// An unreachable cloud only earns the banner after this long, so a NAS
    /// that is simply "at home" while you're out doesn't nag.
    static let unreachableGrace: TimeInterval = 24 * 60 * 60

    static func build(
        remotes: [Remote],
        statuses: [String: RemoteStatus],
        quotas: [String: StorageQuota],
        activeTransfers: [Transfer],
        isInFinder: (String) -> Bool,
        providerName: (String) -> String,
        lastConnected: [String: Date],
        dismissedSuggestions: Set<String>,
        daemon: RcloneDaemon.Status,
        now: Date,
        backups: [BackupJob] = [],
        busyBackups: Set<UUID> = [],
        backupCatchUpPending: Bool = false,
        calendar: Calendar = .autoupdatingCurrent,
        resolveType: (Remote) -> String = { $0.type }
    ) -> CloudSummary {
        let rows = remotes.enumerated().map { index, remote in
            let type = resolveType(remote)
            return row(for: remote, type: type, index: index,
                status: statuses[remote.name] ?? .unknown,
                quota: quotas[remote.name],
                transfers: activeTransfers.filter { $0.involves(remote: remote.name) },
                isInFinder: isInFinder(remote.name),
                providerName: providerName(type),
                lastConnected: lastConnected[remote.name])
        }

        let attention = attentionRow(in: rows, now: now)
        let overall: CloudSummary.Overall
        switch daemon {
        case .idle, .starting: overall = .starting
        case .error(let message): overall = .engineDown(message)
        case .connected:
            if rows.isEmpty {
                overall = .noClouds
            } else if let attention {
                overall = .needsAttention(attention)
            } else if let busy = busySummary(activeTransfers, cloudNames: Set(remotes.map(\.name))) {
                overall = .busy(busy)
            } else {
                overall = .allReady
            }
        }

        let totals = StorageTotals(quotas: rows.compactMap(\.quota))

        return CloudSummary(
            rows: rows,
            overall: overall,
            attention: attention,
            suggestions: suggestions(
                for: rows, backups: backups, busyBackups: busyBackups, backupCatchUpPending: backupCatchUpPending,
                dismissed: dismissedSuggestions, now: now, calendar: calendar),
            usedBytes: totals.usedBytes,
            freeBytes: totals.freeBytes,
            capacityBytes: totals.capacityBytes
        )
    }

    // MARK: - Rows

    private static func row(
        for remote: Remote, type: String, index: Int, status: RemoteStatus, quota: StorageQuota?,
        transfers: [Transfer], isInFinder: Bool, providerName: String, lastConnected: Date?
    ) -> CloudSummary.Row {
        let health: CloudSummary.Health
        var sentence: String
        var detail: String?

        let uploads = transfers.filter { $0.dstFs.hasPrefix("\(remote.name):") }
        let downloads = transfers.filter { !$0.dstFs.hasPrefix("\(remote.name):") }
        if !uploads.isEmpty {
            health = .busy
            sentence = busySentence(verb: "Uploading", uploads)
        } else if !downloads.isEmpty {
            health = .busy
            sentence = busySentence(verb: "Downloading", downloads)
        } else {
            switch status {
            case .authNeeded:
                health = .needsSignIn
                sentence = status.shortText
            case .unreachable(let reason):
                health = .unreachable
                sentence = status.shortText
                detail = reason
            case .error(let reason):
                health = .failing
                sentence = status.shortText
                detail = reason
            case .unknown:
                health = .checking
                sentence = status.shortText
            case .connected:
                health = .ready
                sentence = status.shortText
            }
        }

        return CloudSummary.Row(
            id: remote.name,
            providerType: type,
            providerName: providerName,
            health: health,
            sentence: sentence,
            quota: quota,
            isInFinder: isInFinder,
            tint: CloudTint.slot(forIndex: index),
            lastConnected: lastConnected,
            errorDetail: detail
        )
    }

    private static func busySentence(verb: String, _ transfers: [Transfer]) -> String {
        let count = transfers.count == 1 ? "1 item" : "\(transfers.count) items"
        if let eta = transfers.compactMap(\.eta).max() {
            return "\(verb) \(count), \(etaText(eta)) left"
        }
        return "\(verb) \(count)"
    }

    static func etaText(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "less than a minute"
        case ..<3600:
            let minutes = Int((seconds / 60).rounded())
            return minutes == 1 ? "1 min" : "\(minutes) min"
        default:
            let hours = Int((seconds / 3600).rounded())
            return hours == 1 ? "about 1 hour" : "about \(hours) hours"
        }
    }

    // MARK: - Overall

    /// Destinations that aren't a configured cloud are local paths, so a
    /// batch where every destination is local reads as a download.
    private static func busySummary(_ active: [Transfer], cloudNames: Set<String>) -> CloudSummary.Busy? {
        guard !active.isEmpty else { return nil }
        let progress = active.map(\.progress).reduce(0, +) / Double(active.count)
        let count = active.count == 1 ? "1 item" : "\(active.count) items"
        let destinations = Set(active.map { cloudName(of: $0.dstFs) })
        let cloudDestinations = destinations.filter { cloudNames.contains($0) }
        let isDownload = cloudDestinations.isEmpty
        let sentence: String
        if isDownload {
            sentence = "Downloading \(count) to this Mac"
        } else if destinations.count == 1, let dest = destinations.first {
            sentence = "Copying \(count) to \(dest)"
        } else {
            sentence = "Copying \(count)"
        }
        let focus = isDownload
            ? active.map { cloudName(of: $0.srcFs) }.first { cloudNames.contains($0) }
            : active.map { cloudName(of: $0.dstFs) }.first { cloudNames.contains($0) }
        return .init(progress: progress, sentence: sentence,
                     direction: isDownload ? .down : .up,
                     focusCloud: focus,
                     eta: active.compactMap(\.eta).max())
    }

    /// needsSignIn beats failing beats long-unreachable; sidebar order breaks
    /// ties. Busy and checking clouds never get the banner.
    private static func attentionRow(in rows: [CloudSummary.Row], now: Date) -> CloudSummary.Row? {
        if let row = rows.first(where: { $0.health == .needsSignIn }) { return row }
        if let row = rows.first(where: { $0.health == .failing }) { return row }
        return rows.first { row in
            guard row.health == .unreachable else { return false }
            guard let last = row.lastConnected else { return true }
            return now.timeIntervalSince(last) > unreachableGrace
        }
    }

    private static func suggestions(
        for rows: [CloudSummary.Row], backups: [BackupJob], busyBackups: Set<UUID>, backupCatchUpPending: Bool,
        dismissed: Set<String>, now: Date, calendar: Calendar
    ) -> [CloudSummary.Suggestion] {
        // A backup that needs you outranks storage tips.
        var result: [CloudSummary.Suggestion] = BackupSuggestions
            .notes(for: backups, now: now, calendar: calendar, busy: busyBackups, catchUpPending: backupCatchUpPending)
            .map { .backup($0) }
        for row in rows where (row.quota?.fraction ?? 0) >= nearlyFullThreshold {
            result.append(.nearlyFull(row))
        }
        for row in rows where row.health == .ready && !row.isInFinder {
            result.append(.notInFinder(row))
        }
        return Array(result.filter { !dismissed.contains($0.id) }.prefix(2))
    }

    static func cloudName(of fs: String) -> String {
        fs.split(separator: ":", maxSplits: 1).first.map(String.init) ?? fs
    }
}

/// One finished transfer, worded for Home's activity list.
struct ActivityLine: Equatable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let isFailure: Bool
    /// The cloud a click should open (the destination).
    let cloud: String

    static func lines(from finished: [Transfer], limit: Int = 5) -> [ActivityLine] {
        finished
            .compactMap { transfer -> ActivityLine? in
                guard let date = transfer.completedAt else { return nil }
                let dest = CloudSummaryBuilder.cloudName(of: transfer.dstFs)
                let item = itemName(of: transfer.srcFs)
                let text: String
                if transfer.origin == .backup {
                    guard let backupText = backupText(for: transfer, item: item) else { return nil }
                    return ActivityLine(id: transfer.id, text: backupText, date: date,
                                        isFailure: backupText.hasSuffix("failed") || backupText.hasSuffix("stopped"),
                                        cloud: dest)
                }
                switch transfer.status {
                case .completed:
                    let verb = switch transfer.operation {
                    case .copy: "Copied"
                    case .move: "Moved"
                    case .sync: "Synced"
                    }
                    text = "\(verb) \(item) to \(dest)"
                case .failed:
                    let verb = switch transfer.operation {
                    case .copy: "copy"
                    case .move: "move"
                    case .sync: "sync"
                    }
                    text = "Couldn't \(verb) \(item) to \(dest)"
                case .cancelled, .active:
                    return nil
                }
                return ActivityLine(id: transfer.id, text: text, date: date,
                                    isFailure: { if case .failed = transfer.status { true } else { false } }(),
                                    cloud: dest)
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// "Backed up Documents to B2", "Backup Documents to B2 failed", or
    /// "Backup Documents to B2 stopped" for a run that hit its removal limit.
    /// Cancelled runs say nothing, like any other cancelled transfer.
    private static func backupText(for transfer: Transfer, item: String) -> String? {
        let title = transfer.backup.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? item
        if case .limitHit = transfer.summary?.outcome { return "Backup \(title) stopped" }
        switch transfer.status {
        case .completed: return "Backed up \(title)"
        case .failed: return "Backup \(title) failed"
        case .cancelled, .active: return nil
        }
    }

    /// "Personal:Photos/Yosemite 2026" → "Yosemite 2026"; a bare "Personal:" → "Personal".
    static func itemName(of fs: String) -> String {
        let parts = fs.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.count > 1 ? String(parts[1]) : ""
        if let last = path.split(separator: "/").last { return String(last) }
        return String(parts.first ?? Substring(fs))
    }
}

/// What Home says about saved backups that need a look. Pure: the caller
/// supplies the clock and calendar. Whether and when a job runs on schedule
/// is `BackupSchedulePlanner`'s call; nothing here re-derives it.
enum BackupSuggestions {
    /// A run that failed stops being news after this long.
    static let failedWindow: TimeInterval = 7 * 24 * 60 * 60
    /// "Hasn't run" needs at least this many missed slots.
    static let missedSlotsMinimum = 3

    /// At most one note per job: stopped, then failed, then hasn't run.
    /// Paused, unapproved and manual jobs never get one, and neither does a
    /// job in `busy` (queued, starting or running): its run is the answer.
    /// While `catchUpPending` (the scheduler is about to run every due job)
    /// no job "hasn't run"; failed and stopped notes still show.
    static func notes(for jobs: [BackupJob], now: Date, calendar: Calendar,
                      busy: Set<UUID> = [], catchUpPending: Bool = false) -> [CloudSummary.BackupNote] {
        let planner = BackupSchedulePlanner(calendar: calendar)
        return jobs.compactMap { job in
            guard !busy.contains(job.id) else { return nil }
            return note(for: job, planner: planner, catchUpPending: catchUpPending, now: now, calendar: calendar)
        }
    }

    private static func note(
        for job: BackupJob, planner: BackupSchedulePlanner, catchUpPending: Bool, now: Date, calendar: Calendar
    ) -> CloudSummary.BackupNote? {
        guard job.isApproved, !job.isPaused, planner.nextRun(for: job) != nil else { return nil }
        if let run = job.lastRun {
            if job.isStoppedAtRemovalLimit {
                return .init(jobID: job.id, kind: .stopped,
                             sentence: "\(job.name) stopped \(when(run.startedAt, now: now, calendar: calendar))",
                             dismissKey: key("stopped", job, run.startedAt))
            }
            if case .failed = run.outcome, now.timeIntervalSince(run.startedAt) <= failedWindow {
                return .init(jobID: job.id, kind: .failed,
                             sentence: "\(job.name) failed \(when(run.startedAt, now: now, calendar: calendar))",
                             dismissKey: key("failed", job, run.startedAt))
            }
        }
        guard !catchUpPending, let first = planner.eligibleNextRun(for: job), first <= now,
              missedSlots(from: first, schedule: job.schedule, now: now, calendar: calendar) >= missedSlotsMinimum
        else { return nil }
        let since = job.lastRun?.startedAt ?? job.approvedAt ?? job.createdAt
        return .init(jobID: job.id, kind: .hasntRun,
                     sentence: "\(job.name) hasn't run in \(elapsed(since: since, now: now, calendar: calendar))",
                     dismissKey: key("overdue", job, since))
    }

    private static func key(_ kind: String, _ job: BackupJob, _ date: Date) -> String {
        "backup-\(kind):\(job.id.uuidString):\(Int(date.timeIntervalSince1970))"
    }

    /// Slots from `first` (the first slot after the anchor) up to `now`,
    /// counting no further than the minimum.
    private static func missedSlots(from first: Date, schedule: BackupSchedule, now: Date, calendar: Calendar) -> Int {
        var count = 0
        var slot: Date? = first
        while let current = slot, current <= now, count < missedSlotsMinimum {
            count += 1
            slot = schedule.nextRun(after: current, calendar: calendar)
        }
        return count
    }

    /// "3 days", "1 day", or "5 hours" when under a day.
    static func elapsed(since: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: since, to: now).day ?? 0
        if days >= 1 { return days == 1 ? "1 day" : "\(days) days" }
        let hours = max(0, calendar.dateComponents([.hour], from: since, to: now).hour ?? 0)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    /// "last night" (6 PM yesterday to 6 AM today), else "today", "yesterday"
    /// or "N days ago", by calendar day.
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           let nightStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday),
           let nightEnd = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today),
           date >= nightStart, date < nightEnd {
            return "last night"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }
}

/// The menu bar glyph: a template SF Symbol per overall state.
enum CompanionGlyph {
    static func symbol(for overall: CloudSummary.Overall) -> String {
        switch overall {
        case .starting, .noClouds, .allReady: "icloud"
        case .busy(let busy): busy.direction == .down ? "icloud.and.arrow.down" : "icloud.and.arrow.up"
        case .needsAttention, .engineDown: "exclamationmark.icloud"
        }
    }

    static func accessibilityLabel(for overall: CloudSummary.Overall) -> String {
        "Nimbus: " + CompanionHeadline.title(for: overall)
    }
}

/// The one-line answer to "is everything okay?", shared by the menu bar
/// label and the companion header.
enum CompanionHeadline {
    static func title(for overall: CloudSummary.Overall) -> String {
        switch overall {
        case .starting: "Starting…"
        case .engineDown: "Nimbus's connection engine stopped"
        case .noClouds: "No clouds yet"
        case .allReady: "Everything is ready"
        case .busy(let busy): busy.sentence
        case .needsAttention(let row):
            switch row.health {
            case .needsSignIn: "\(row.name) needs you to sign in"
            case .failing: "Nimbus can't connect to \(row.name)"
            default: "\(row.name) can't be reached"
            }
        }
    }
}

/// Home's hero: the one big line and the sentence under it.
enum HomeHeadline {
    /// Free space when any cloud has a limit; otherwise usage, because
    /// pay-as-you-go storage has no "free"; otherwise how many clouds.
    static func title(for summary: CloudSummary) -> String {
        if let free = summary.freeBytes { return "\(ByteText.format(free)) free" }
        if summary.usedBytes > 0 { return "\(ByteText.format(summary.usedBytes)) used" }
        return cloudCount(summary)
    }

    /// What's used and where, then the same status line the menu bar shows.
    static func sentence(for summary: CloudSummary) -> String {
        var parts: [String] = []
        if summary.freeBytes != nil {
            parts.append("\(ByteText.format(summary.usedBytes)) used across \(cloudCount(summary)).")
        } else if summary.usedBytes > 0 {
            parts.append("Across \(cloudCount(summary)).")
        }
        let status = CompanionHeadline.title(for: summary.overall)
        let ended = status.last.map { ".…!?".contains($0) } ?? false
        parts.append(ended ? status : status + ".")
        return parts.joined(separator: " ")
    }

    private static func cloudCount(_ summary: CloudSummary) -> String {
        summary.rows.count == 1 ? "1 cloud" : "\(summary.rows.count) clouds"
    }
}

extension CloudSummaryBuilder {
    /// The summary for the live app state. One entry point so Home, the
    /// companion and the menu bar label can never compute it differently.
    @MainActor
    static func live(
        remotes: [Remote], status: RemoteStatusService, transfers: TransferStore,
        providers: ProviderDirectory, settings: AppSettings, daemon: RcloneDaemon,
        backups: BackupStore, runner: BackupRunner, scheduler: BackupScheduler
    ) -> CloudSummary {
        build(
            remotes: remotes,
            statuses: status.statuses,
            quotas: status.quotas,
            activeTransfers: transfers.activeTransfers,
            isInFinder: { FinderIntegration.isShown(remote: $0, settings: settings) },
            providerName: { CloudNaming.providerName(forType: $0, directory: providers) },
            lastConnected: status.lastConnected,
            dismissedSuggestions: settings.dismissedSuggestions,
            daemon: daemon.status,
            now: Date(),
            backups: backups.jobs,
            busyBackups: runner.busyJobIDs,
            backupCatchUpPending: scheduler.isCatchUpPending,
            resolveType: { CloudNaming.resolvedType(of: $0, in: remotes) }
        )
    }
}
