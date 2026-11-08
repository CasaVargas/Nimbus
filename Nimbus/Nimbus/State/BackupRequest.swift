import Foundation
import RcloneKit

/// The one place a `BackupJob` becomes an rclone call. The preview, the
/// real run and the "Copy rclone Command" text all come from here, so a
/// preview can't drift from what the run does.
enum BackupRequest {
    static let versionsExcludeRule = "/\(BackupJob.versionsFolderName)/**"

    /// Folder name for one run's versions: `yyyy-MM-dd HHmmss`, local time.
    static func stamp(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: date)
    }

    static func make(job: BackupJob, dryRun: Bool, stamp: String) -> SyncRequest {
        var reports: Set<SyncReportKind> = []
        if dryRun {
            reports = [.missingOnDst, .differ, .error]
            // sync/copy lists destination-only files too, though copy never
            // removes them, so only a mirror asks for that list.
            if job.mode == .mirror { reports.insert(.missingOnSrc) }
        }
        return SyncRequest(
            operation: job.mode == .mirror ? .sync : .copy,
            srcFs: job.source.fs,
            dstFs: job.destination.fs,
            dryRun: dryRun,
            backupDir: job.versionsEndpoint?.appending(stamp).fs,
            maxDelete: job.mode == .mirror ? job.removalLimit : nil,
            excludeRules: excludeRules(for: job),
            reports: reports
        )
    }

    /// The user's excludes, plus the versions folder when it sits inside the
    /// destination (rclone refuses an overlapping backup dir otherwise).
    static func excludeRules(for job: BackupJob) -> [String] {
        var rules = job.excludes
        if job.versions.enabled, job.versions.location == .insideDestination {
            rules.append(versionsExcludeRule)
        }
        return rules
    }

    /// The equivalent CLI, for pasting into a terminal or cron. Every
    /// argument is single-quoted for zsh/bash; the backup dir ends with a
    /// `$(date …)` stamp outside the quotes so each run gets its own folder.
    static func cliCommand(job: BackupJob) -> String {
        var parts = ["rclone", job.mode == .mirror ? "sync" : "copy", quote(job.source.fs), quote(job.destination.fs)]
        for rule in excludeRules(for: job) {
            parts += ["--exclude", quote(rule)]
        }
        if let versions = job.versionsEndpoint {
            parts += ["--backup-dir", quote(versions.fs + "/") + #""$(date +'%Y-%m-%d %H%M%S')""#]
        }
        if job.mode == .mirror, let limit = job.removalLimit {
            parts += ["--max-delete", String(limit)]
        }
        return parts.joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
