import Foundation

/// Decides which saved backups are due and when to wake next. Pure: the
/// caller supplies the clock and the set of jobs already queued or running.
///
/// A job's next run is the first slot after the start of its last attempt
/// (or after approval if it never ran). A failed run is not retried early,
/// and any number of missed slots yields a single run.
struct BackupSchedulePlanner {
    let calendar: Calendar

    /// Jobs whose next run is at or before `now`: scheduled, approved, not paused, not queued or running.
    func dueJobs(_ jobs: [BackupJob], now: Date, busy: Set<UUID>) -> [UUID] {
        jobs.compactMap { job in
            guard !busy.contains(job.id), let next = eligibleNextRun(for: job), next <= now else { return nil }
            return job.id
        }
    }

    /// The earliest future next run among eligible jobs, or nil.
    func nextWake(_ jobs: [BackupJob], now: Date) -> Date? {
        jobs.compactMap { eligibleNextRun(for: $0) }.filter { $0 > now }.min()
    }

    /// Anchor = lastRun?.startedAt ?? approvedAt ?? createdAt. Nil for manual jobs.
    func nextRun(for job: BackupJob) -> Date? {
        let anchor = job.lastRun?.startedAt ?? job.approvedAt ?? job.createdAt
        return job.schedule.nextRun(after: anchor, calendar: calendar)
    }

    private func eligibleNextRun(for job: BackupJob) -> Date? {
        guard job.isApproved, !job.isPaused else { return nil }
        return nextRun(for: job)
    }
}
