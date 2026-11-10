import Foundation

/// The editor's schedule controls as plain values. It keeps the time and
/// weekday while the kind changes, so flipping Daily to Weekly and back
/// doesn't lose what was picked.
struct BackupScheduleDraft: Equatable {
    enum Kind: CaseIterable, Hashable {
        case manual, hourly, daily, weekly

        var label: String {
            switch self {
            case .manual: String(localized: "Manual only")
            case .hourly: String(localized: "Every hour")
            case .daily: String(localized: "Every day at a time")
            case .weekly: String(localized: "Every week on a weekday at a time")
            }
        }

        var showsTime: Bool { self == .daily || self == .weekly }
        var showsWeekday: Bool { self == .weekly }
    }

    var kind: Kind
    /// 1 = Sunday, as in `BackupSchedule.weekly`.
    var weekday = 1
    var hour = 2
    var minute = 0

    init(_ schedule: BackupSchedule) {
        switch schedule {
        case .manual:
            kind = .manual
        case .hourly:
            kind = .hourly
        case .daily(let hour, let minute):
            kind = .daily
            self.hour = hour
            self.minute = minute
        case .weekly(let weekday, let hour, let minute):
            kind = .weekly
            self.weekday = weekday
            self.hour = hour
            self.minute = minute
        }
    }

    var schedule: BackupSchedule {
        switch kind {
        case .manual: .manual
        case .hourly: .hourly
        case .daily: .daily(hour: hour, minute: minute)
        case .weekly: .weekly(weekday: weekday, hour: hour, minute: minute)
        }
    }

    /// The time as a date today, for a `DatePicker`.
    func timeDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    mutating func setTime(from date: Date, calendar: Calendar = .current) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
}
