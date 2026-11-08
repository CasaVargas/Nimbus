import Foundation

/// The status sentence and tint for one backup row. Pure, so every row of
/// the spec's status table is unit-tested. First match wins.
struct BackupStatus: Equatable {
    enum Tint: Equatable { case info, secondary, warning, error, ok }

    let sentence: String
    let tint: Tint
    /// Non-nil while the backup runs.
    let progress: Double?

    static func make(job: BackupJob, isRunning: Bool, isQueued: Bool, transfer: Transfer?, now: Date) -> BackupStatus {
        if isRunning {
            let progress = transfer?.progress ?? 0
            var sentence = String(localized: "Backing up… \(Int((progress * 100).rounded(.down)))%")
            if let eta = transfer?.eta, let left = etaText(eta) {
                sentence += ", " + left
            }
            return BackupStatus(sentence: sentence, tint: .info, progress: progress)
        }
        if isQueued {
            return BackupStatus(sentence: String(localized: "Waiting for another backup to finish"), tint: .secondary, progress: nil)
        }
        if !job.isApproved {
            return BackupStatus(sentence: String(localized: "Preview needed before it can run"), tint: .warning, progress: nil)
        }
        if job.isPaused {
            return BackupStatus(sentence: String(localized: "Paused"), tint: .secondary, progress: nil)
        }
        guard let lastRun = job.lastRun else {
            return BackupStatus(sentence: String(localized: "Not run yet"), tint: .secondary, progress: nil)
        }
        let when = relative(lastRun.finishedAt, now: now)
        switch lastRun.outcome {
        case .failed(let message):
            return BackupStatus(sentence: String(localized: "Failed \(when): \(message)"), tint: .error, progress: nil)
        case .limitHit:
            let limit = job.removalLimit ?? 0
            return BackupStatus(
                sentence: String(localized: "Stopped \(when): would remove more than \(limit) files"),
                tint: .warning, progress: nil
            )
        case .cancelled:
            return BackupStatus(sentence: String(localized: "Stopped \(when)"), tint: .secondary, progress: nil)
        case .completed:
            let detail: String = switch lastRun.copied {
            case 0: String(localized: "no changes")
            case 1: String(localized: "1 file")
            default: String(localized: "\(lastRun.copied) files")
            }
            return BackupStatus(sentence: String(localized: "Backed up \(when), \(detail)"), tint: .ok, progress: nil)
        }
    }

    /// "Every day at 2:00 AM · next tomorrow at 2:00 AM", or "Manual".
    static func scheduleLine(job: BackupJob, now: Date, calendar: Calendar = .current) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone)
        func at(_ hour: Int, _ minute: Int) -> String {
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            return date.formatted(time)
        }
        let base: String
        switch job.schedule {
        case .manual:
            return String(localized: "Manual")
        case .hourly:
            base = String(localized: "Every hour")
        case .daily(let hour, let minute):
            base = String(localized: "Every day at \(at(hour, minute))")
        case .weekly(let weekday, let hour, let minute):
            let symbols = calendar.weekdaySymbols
            let day = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
            base = String(localized: "Every \(day) at \(at(hour, minute))")
        }
        guard !job.isPaused, job.isApproved,
              let next = job.schedule.nextRun(after: now, calendar: calendar) else { return base }
        return base + " · " + String(localized: "next \(nextText(next, now: now, calendar: calendar))")
    }

    static func accessibilityLabel(job: BackupJob, status: BackupStatus, scheduleLine: String) -> String {
        "\(job.name), \(status.sentence), \(scheduleLine)"
    }

    /// "2 hours ago", "yesterday".
    static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func etaText(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 60 { return String(localized: "less than a minute left") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = seconds >= 3600 ? 2 : 1
        guard let text = formatter.string(from: seconds) else { return nil }
        return String(localized: "\(text) left")
    }

    private static func nextText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today at \(time)") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)")
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: calendar.timeZone)
        style.calendar = calendar
        return String(localized: "\(date.formatted(style)) at \(time)")
    }
}
