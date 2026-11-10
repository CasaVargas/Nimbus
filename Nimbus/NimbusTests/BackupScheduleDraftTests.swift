import Foundation
import Testing
@testable import Nimbus

@Suite("Backup schedule editor")
struct BackupScheduleDraftTests {
    @Test(arguments: [
        BackupSchedule.manual,
        .hourly,
        .daily(hour: 2, minute: 30),
        .weekly(weekday: 6, hour: 21, minute: 5),
    ])
    func draftRoundTripsEveryKind(_ schedule: BackupSchedule) {
        #expect(BackupScheduleDraft(schedule).schedule == schedule)
    }

    @Test func kindLabelsUseTheSpecsWording() {
        #expect(BackupScheduleDraft.Kind.allCases.map(\.label) == [
            "Manual only", "Every hour", "Every day at a time", "Every week on a weekday at a time",
        ])
    }

    @Test func switchingKindKeepsTheTimeTheUserPicked() {
        var draft = BackupScheduleDraft(.daily(hour: 7, minute: 15))
        draft.kind = .weekly
        #expect(draft.schedule == .weekly(weekday: 1, hour: 7, minute: 15))
        draft.kind = .manual
        #expect(draft.schedule == .manual)
        draft.kind = .daily
        #expect(draft.schedule == .daily(hour: 7, minute: 15))
    }

    @Test func timeAndWeekdayControlsFollowTheKind() {
        #expect(!BackupScheduleDraft.Kind.hourly.showsTime)
        #expect(BackupScheduleDraft.Kind.daily.showsTime)
        #expect(!BackupScheduleDraft.Kind.daily.showsWeekday)
        #expect(BackupScheduleDraft.Kind.weekly.showsTime)
        #expect(BackupScheduleDraft.Kind.weekly.showsWeekday)
    }

    @Test func timeConvertsToAndFromADate() {
        var draft = BackupScheduleDraft(.daily(hour: 2, minute: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nine45 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 21, minute: 45))!
        draft.setTime(from: nine45, calendar: calendar)
        #expect(draft.schedule == .daily(hour: 21, minute: 45))
        let date = draft.timeDate(now: nine45, calendar: calendar)
        #expect(calendar.component(.hour, from: date) == 21)
        #expect(calendar.component(.minute, from: date) == 45)
    }

    @Test func newJobsDefaultToManual() {
        #expect(BackupScheduleDraft(.manual).kind == .manual)
    }
}

@Suite("Open at Login note")
struct OpenAtLoginNoteTests {
    @Test func showsOnlyForAScheduleWhileOpenAtLoginIsOff() {
        #expect(OpenAtLoginNote.isShown(schedules: [.daily(hour: 2, minute: 0)], openAtLoginIsOn: false))
        #expect(OpenAtLoginNote.isShown(schedules: [.manual, .hourly], openAtLoginIsOn: false))
        #expect(!OpenAtLoginNote.isShown(schedules: [.manual, .manual], openAtLoginIsOn: false))
        #expect(!OpenAtLoginNote.isShown(schedules: [], openAtLoginIsOn: false))
        #expect(!OpenAtLoginNote.isShown(schedules: [.hourly], openAtLoginIsOn: true))
    }

    @Test func copyIsTheSpecs() {
        #expect(OpenAtLoginNote.text == "Scheduled backups run while Nimbus is open, including from the menu bar.")
    }
}
