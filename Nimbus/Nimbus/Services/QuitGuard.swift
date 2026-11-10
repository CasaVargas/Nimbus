import Foundation

/// Whether Quit Nimbus asks first. Pure, so the rule is tested without an
/// `NSAlert`. Logout and restart never ask: the system is already ending the
/// session, and a blocked quit would stall it.
enum QuitDecision: Equatable {
    case quit
    case askFirst

    static func make(isBackupRunning: Bool, isPowerOff: Bool) -> QuitDecision {
        isBackupRunning && !isPowerOff ? .askFirst : .quit
    }

    /// The spec's sentence, true only when an interrupted job runs again on
    /// its schedule; otherwise only that the backup stops.
    static func alertMessage(runsAgain: Bool) -> String {
        runsAgain
            ? "A backup is running. If you quit, it stops and runs again the next time Nimbus opens."
            : "A backup is running. If you quit, it stops."
    }

    /// Whether any of the running or queued `jobs` runs again after a quit:
    /// it has a schedule and isn't paused, so the next launch catches it up.
    static func runsAgain(interrupting jobs: [BackupJob]) -> Bool {
        jobs.contains { $0.schedule != .manual && !$0.isPaused }
    }
}
