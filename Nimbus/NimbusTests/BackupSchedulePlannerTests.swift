import Foundation
import Testing
@testable import Nimbus

struct BackupSchedulePlannerTests {
    static let planner = BackupSchedulePlanner(calendar: BackupJobTests.newYork)

    static func date(_ string: String) -> Date { BackupJobTests.date(string) }

    static func summary(startedAt: Date, outcome: BackupRunSummary.Outcome = .completed) -> BackupRunSummary {
        BackupRunSummary(
            startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(60),
            trigger: .scheduled, outcome: outcome,
            copied: 0, replaced: 0, removed: 0, errors: 0, bytes: 0
        )
    }

    /// An approved, unpaused daily 02:00 job created well before any test clock.
    static func job(
        schedule: BackupSchedule = .daily(hour: 2, minute: 0),
        lastRunStart: Date? = nil,
        outcome: BackupRunSummary.Outcome = .completed
    ) -> BackupJob {
        var job = BackupJobTests.job()
        job.schedule = schedule
        job.approvedFingerprint = job.fingerprint
        job.approvedAt = date("2026-11-01T08:00:00-05:00")
        job.lastRun = lastRunStart.map { summary(startedAt: $0, outcome: outcome) }
        return job
    }

    @Test func missedSlotsRunOnce() {
        let job = Self.job(lastRunStart: Self.date("2026-11-07T02:00:00-05:00"))
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.dueJobs([job], now: now, busy: []) == [job.id])
    }

    @Test func pausedNeverDue() {
        var job = Self.job(lastRunStart: Self.date("2026-11-07T02:00:00-05:00"))
        job.isPaused = true
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.dueJobs([job], now: now, busy: []).isEmpty)
        #expect(Self.planner.nextWake([job], now: now) == nil)
    }

    @Test func unapprovedNeverDue() {
        var job = Self.job(lastRunStart: Self.date("2026-11-07T02:00:00-05:00"))
        job.approvedFingerprint = nil
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.dueJobs([job], now: now, busy: []).isEmpty)
        #expect(Self.planner.nextWake([job], now: now) == nil)
    }

    @Test func busyNotDueTwice() {
        let job = Self.job(lastRunStart: Self.date("2026-11-07T02:00:00-05:00"))
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.dueJobs([job], now: now, busy: [job.id]).isEmpty)
    }

    @Test func manualNeverDue() {
        let job = Self.job(schedule: .manual, lastRunStart: Self.date("2026-11-07T02:00:00-05:00"))
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.nextRun(for: job) == nil)
        #expect(Self.planner.dueJobs([job], now: now, busy: []).isEmpty)
        #expect(Self.planner.nextWake([job], now: now) == nil)
    }

    @Test func failedRunWaitsForNextSlot() {
        let job = Self.job(lastRunStart: Self.date("2026-11-10T02:00:00-05:00"), outcome: .failed("boom"))
        let now = Self.date("2026-11-10T09:00:00-05:00")
        #expect(Self.planner.dueJobs([job], now: now, busy: []).isEmpty)
        #expect(Self.planner.nextRun(for: job) == Self.date("2026-11-11T02:00:00-05:00"))
    }

    @Test func nextWakeIsEarliest() {
        let now = Self.date("2026-11-10T09:00:00-05:00")
        let daily = Self.job(lastRunStart: Self.date("2026-11-10T02:00:00-05:00"))
        let hourly = Self.job(schedule: .hourly, lastRunStart: Self.date("2026-11-10T08:30:00-05:00"))
        // hourly's slot after 08:30 is 09:00, which is not strictly future; use a later start.
        let hourlyLater = Self.job(schedule: .hourly, lastRunStart: Self.date("2026-11-10T09:10:00-05:00"))
        #expect(Self.planner.nextWake([daily, hourlyLater], now: now) == Self.date("2026-11-10T10:00:00-05:00"))
        #expect(Self.planner.nextWake([daily], now: now) == Self.date("2026-11-11T02:00:00-05:00"))
        // A job that is already due is not a wake time.
        #expect(Self.planner.nextWake([hourly], now: now) == nil)
        #expect(Self.planner.nextWake([], now: now) == nil)
    }

    @Test func neverRunAnchorsOnApproval() {
        var job = Self.job()
        job.approvedAt = Self.date("2026-11-10T10:00:00-05:00")
        let now = Self.date("2026-11-10T11:00:00-05:00")
        #expect(Self.planner.nextRun(for: job) == Self.date("2026-11-11T02:00:00-05:00"))
        #expect(Self.planner.dueJobs([job], now: now, busy: []).isEmpty)
    }

    @Test func neverRunWithoutApprovalDateAnchorsOnCreation() {
        var job = Self.job()
        job.approvedAt = nil
        #expect(Self.planner.nextRun(for: job) != nil)
        #expect(Self.planner.nextRun(for: job) == BackupSchedule.daily(hour: 2, minute: 0)
            .nextRun(after: job.createdAt, calendar: BackupJobTests.newYork))
    }
}
