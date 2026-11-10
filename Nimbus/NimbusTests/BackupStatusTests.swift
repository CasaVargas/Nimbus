import Foundation
import Testing
@testable import Nimbus

struct BackupStatusTests {
    let now = Date(timeIntervalSince1970: 1_794_085_200) // 2026-11-08 16:00 EST

    static var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func job(approved: Bool = true, _ mutate: (inout BackupJob) -> Void = { _ in }) -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/Documents"),
                                destination: .cloud(remote: "b2", path: "mac"), now: now)
        mutate(&job)
        if approved { job.approvedFingerprint = job.fingerprint }
        return job
    }

    private func run(_ outcome: BackupRunSummary.Outcome, copied: Int = 12, hoursAgo: Double = 2) -> BackupRunSummary {
        let finished = now.addingTimeInterval(-hoursAgo * 3600)
        return BackupRunSummary(startedAt: finished.addingTimeInterval(-60), finishedAt: finished,
                                trigger: .manual, outcome: outcome, copied: copied, replaced: 0,
                                removed: 0, errors: 0, bytes: 0)
    }

    private func transfer(progress: Double, eta: TimeInterval?) -> Transfer {
        Transfer(jobID: 1, operation: .sync, srcFs: "a", dstFs: "b", startedAt: now, status: .active,
                 origin: .backup, nimbusUUID: UUID(), progress: progress, eta: eta)
    }

    @Test func runningBeatsEverything() {
        let job = job(approved: false) { $0.isPaused = true; $0.lastRun = run(.failed("x")) }
        let status = BackupStatus.make(job: job, isRunning: true, isQueued: true,
                                       transfer: transfer(progress: 0.45, eta: 180), now: now)
        #expect(status.sentence == "Backing up… 45%, 3 min left")
        #expect(status.tint == .info)
        #expect(status.progress == 0.45)
    }

    @Test func runningWithoutEta() {
        let status = BackupStatus.make(job: job(), isRunning: true, isQueued: false,
                                       transfer: transfer(progress: 0.1, eta: nil), now: now)
        #expect(status.sentence == "Backing up… 10%")
    }

    @Test func queued() {
        let status = BackupStatus.make(job: job(), isRunning: false, isQueued: true, transfer: nil, now: now)
        #expect(status.sentence == "Waiting for another backup to finish")
        #expect(status.tint == .secondary)
        #expect(status.progress == nil)
    }

    @Test func notApproved() {
        let status = BackupStatus.make(job: job(approved: false) { $0.lastRun = run(.completed) },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(status.sentence == "Preview needed before it can run")
        #expect(status.tint == .warning)
    }

    @Test func paused() {
        let status = BackupStatus.make(job: job { $0.isPaused = true; $0.lastRun = run(.failed("x")) },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(status.sentence == "Paused")
        #expect(status.tint == .secondary)
    }

    @Test func failed() {
        let summary = run(.failed("The source folder isn't available. Is the drive connected?"))
        let status = BackupStatus.make(job: job { $0.lastRun = summary },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        let relative = BackupStatus.relative(summary.finishedAt, now: now)
        #expect(status.sentence == "Failed \(relative): The source folder isn't available. Is the drive connected?")
        #expect(status.tint == .error)
    }

    @Test func limitHit() {
        let summary = run(.limitHit)
        let status = BackupStatus.make(job: job { $0.removalLimit = 100; $0.lastRun = summary },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        let relative = BackupStatus.relative(summary.finishedAt, now: now)
        #expect(status.sentence == "Stopped \(relative): would remove more than 100 files")
        #expect(status.tint == .warning)
    }

    @Test func completed() {
        let summary = run(.completed, copied: 12)
        let status = BackupStatus.make(job: job { $0.lastRun = summary },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        let relative = BackupStatus.relative(summary.finishedAt, now: now)
        #expect(status.sentence == "Backed up \(relative), 12 files")
        #expect(status.tint == .ok)
        #expect(relative == "2 hours ago")
    }

    @Test func completedSingularAndNoChanges() {
        let one = BackupStatus.make(job: job { $0.lastRun = run(.completed, copied: 1) },
                                    isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(one.sentence.hasSuffix(", 1 file"))
        let none = BackupStatus.make(job: job { $0.lastRun = run(.completed, copied: 0) },
                                     isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(none.sentence.hasSuffix(", no changes"))
    }

    @Test func cancelledLastRun() {
        let summary = run(.cancelled)
        let status = BackupStatus.make(job: job { $0.lastRun = summary },
                                       isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(status.sentence == "Stopped \(BackupStatus.relative(summary.finishedAt, now: now))")
        #expect(status.tint == .secondary)
    }

    @Test func neverRun() {
        let status = BackupStatus.make(job: job(), isRunning: false, isQueued: false, transfer: nil, now: now)
        #expect(status.sentence == "Not run yet")
        #expect(status.tint == .secondary)
    }

    @Test func scheduleLineManual() {
        #expect(BackupStatus.scheduleLine(job: job(), now: now, calendar: Self.newYork) == "Manual")
    }

    @Test func scheduleLineDaily() {
        let line = BackupStatus.scheduleLine(job: job { $0.schedule = .daily(hour: 2, minute: 0) },
                                             now: now, calendar: Self.newYork)
        #expect(line.hasPrefix("Every day at 2:00"))
        #expect(line.contains(" · next "))
    }

    @Test func scheduleLinePausedHasNoNext() {
        let line = BackupStatus.scheduleLine(job: job { $0.schedule = .hourly; $0.isPaused = true },
                                             now: now, calendar: Self.newYork)
        #expect(line == "Every hour")
    }

    /// Started `hoursAgo` before `now` (16:00).
    private func started(_ outcome: BackupRunSummary.Outcome, hoursAgo: Double) -> BackupRunSummary {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return BackupRunSummary(startedAt: start, finishedAt: start.addingTimeInterval(60),
                                trigger: .scheduled, outcome: outcome, copied: 0, replaced: 0,
                                removed: 0, errors: 0, bytes: 0)
    }

    @Test func scheduleLineOverdueHasNoNext() {
        // Last ran three days ago at 02:00: its next run is past, waiting for catch-up.
        let line = BackupStatus.scheduleLine(
            job: job { $0.schedule = .daily(hour: 2, minute: 0); $0.lastRun = started(.completed, hoursAgo: 86) },
            now: now, calendar: Self.newYork)
        #expect(line.hasPrefix("Every day at 2:00"))
        #expect(!line.contains("next"))
    }

    @Test func scheduleLineLimitHitHasNoNext() {
        let line = BackupStatus.scheduleLine(
            job: job { $0.schedule = .daily(hour: 2, minute: 0); $0.lastRun = started(.limitHit, hoursAgo: 14) },
            now: now, calendar: Self.newYork)
        #expect(line.hasPrefix("Every day at 2:00"))
        #expect(!line.contains("next"))
    }

    @Test func scheduleLineAfterThisMorningsRunShowsPlannersSlot() {
        // A daily 02:00 job that ran at 02:00 this morning.
        let daily = job { $0.schedule = .daily(hour: 2, minute: 0); $0.lastRun = started(.completed, hoursAgo: 14) }
        let line = BackupStatus.scheduleLine(job: daily, now: now, calendar: Self.newYork)
        let time = BackupJobTests.date("2026-11-09T02:00:00-05:00")
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Self.newYork.timeZone))
        #expect(line.hasSuffix(" · next tomorrow at \(time)"))
    }

    @Test func scheduleLineHourlyFollowsLastRunNotTheClock() {
        // Ran at 15:30; the planner's next slot, 16:00, is now and so already
        // due: no "next" (the clock alone would say 17:00).
        let line = BackupStatus.scheduleLine(
            job: job { $0.schedule = .hourly; $0.lastRun = started(.completed, hoursAgo: 0.5) },
            now: now, calendar: Self.newYork)
        #expect(line == "Every hour")
    }

    @Test func scheduleLineUnapprovedHasNoNext() {
        let line = BackupStatus.scheduleLine(job: job(approved: false) { $0.schedule = .hourly },
                                             now: now, calendar: Self.newYork)
        #expect(line == "Every hour")
    }

    @Test func accessibilityLabelIsOneSentence() {
        let job = job { $0.name = "Documents to B2"; $0.lastRun = run(.completed) }
        let status = BackupStatus.make(job: job, isRunning: false, isQueued: false, transfer: nil, now: now)
        let label = BackupStatus.accessibilityLabel(job: job, status: status, scheduleLine: "Manual")
        #expect(label == "Documents to B2, \(status.sentence), Manual")
    }

    /// The Backups screen's clock ticks once a minute, so a run that ends
    /// mid-minute is ahead of it until the next tick.
    @Test func relativeNeverReadsAsTheFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BackupStatus.relative(now.addingTimeInterval(36), now: now) == BackupStatus.relative(now, now: now))
        #expect(!BackupStatus.relative(now.addingTimeInterval(36), now: now).hasPrefix("in "))
    }

    @Test func fileCountsAgreeInNumber() {
        #expect(BackupStatus.fileCount(1) == "1 file")
        #expect(BackupStatus.fileCount(2) == "2 files")
        #expect(BackupStatus.fileCount(0) == "0 files")
    }
}
