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
        let progress: Double
        let sentence: String
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

        var id: String {
            switch self {
            case .nearlyFull(let row): "full:\(row.id)"
            case .notInFinder(let row): "finder:\(row.id)"
            }
        }
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
            } else if let busy = busySummary(activeTransfers, now: now) {
                overall = .busy(busy)
            } else {
                overall = .allReady
            }
        }

        var used: Int64 = 0
        var free: Int64?
        var capacity: Int64 = 0
        for row in rows {
            guard let quota = row.quota else { continue }
            if let u = quota.used { used += u }
            if let total = quota.total {
                capacity += total
                if let f = quota.free { free = (free ?? 0) + f }
            } else if let u = quota.used {
                capacity += u
            }
        }

        return CloudSummary(
            rows: rows,
            overall: overall,
            attention: attention,
            suggestions: suggestions(for: rows, dismissed: dismissedSuggestions),
            usedBytes: used,
            freeBytes: free,
            capacityBytes: capacity
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

    private static func busySummary(_ active: [Transfer], now: Date) -> CloudSummary.Busy? {
        guard !active.isEmpty else { return nil }
        let progress = active.map(\.progress).reduce(0, +) / Double(active.count)
        let count = active.count == 1 ? "1 item" : "\(active.count) items"
        let destinations = Set(active.map { cloudName(of: $0.dstFs) })
        let sentence: String
        if destinations.count == 1, let dest = destinations.first {
            sentence = "Copying \(count) to \(dest)"
        } else {
            sentence = "Copying \(count)"
        }
        return .init(progress: progress, sentence: sentence)
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
        for rows: [CloudSummary.Row], dismissed: Set<String>
    ) -> [CloudSummary.Suggestion] {
        var result: [CloudSummary.Suggestion] = []
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

    /// "Personal:Photos/Yosemite 2026" → "Yosemite 2026"; a bare "Personal:" → "Personal".
    static func itemName(of fs: String) -> String {
        let parts = fs.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.count > 1 ? String(parts[1]) : ""
        if let last = path.split(separator: "/").last { return String(last) }
        return String(parts.first ?? Substring(fs))
    }
}
