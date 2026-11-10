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

    static let alertMessage = "A backup is running. If you quit, it stops and runs again the next time Nimbus opens."
}
