import Foundation
import Observation
import os
import ServiceManagement

/// A launch by the backups agent (`--background-backups`): Nimbus was quit,
/// so it starts hidden, runs the due backups and quits when idle. Spec:
/// backups design, decision 1 "Revisited".
enum BackgroundLaunch {
    static let argument = "--background-backups"

    static func isBackgroundLaunch(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
    }
}

/// Whether a background-launched Nimbus quits now. Pure, so the rule is
/// tested without a running app.
enum BackgroundQuitDecision {
    /// How long a background launch waits for the scheduler to start (the
    /// daemon connecting) before giving up.
    static let startDeadline: TimeInterval = 10 * 60

    /// - Parameters:
    ///   - isBackgroundLaunch: launched by the agent.
    ///   - userTookOver: the user has since used the app; it stays open.
    ///   - schedulerStarted: the daemon connected and the scheduler is running.
    ///   - isCatchUpPending: a catch-up pass is scheduled or enqueueing.
    ///   - isBackupBusy: a backup is queued, starting or running.
    ///   - elapsed: seconds since launch.
    static func shouldQuit(
        isBackgroundLaunch: Bool,
        userTookOver: Bool,
        schedulerStarted: Bool,
        isCatchUpPending: Bool,
        isBackupBusy: Bool,
        elapsed: TimeInterval
    ) -> Bool {
        guard isBackgroundLaunch, !userTookOver else { return false }
        guard schedulerStarted else { return elapsed >= startDeadline }
        return !isCatchUpPending && !isBackupBusy
    }
}

/// Due backups a background launch can't run because they changed since
/// their last approval: each gets one "needs a preview" notification per
/// fingerprint instead of a sheet.
enum BackupReviewNotices {
    /// Jobs that would be due now, were approved once, and changed since.
    /// Never-approved, paused and manual jobs are left out.
    static func jobsNeedingReview(_ jobs: [BackupJob], planner: BackupSchedulePlanner, now: Date) -> [BackupJob] {
        jobs.filter { job in
            guard job.approvedFingerprint != nil, !job.isApproved, !job.isPaused,
                  let next = planner.nextRun(for: job) else { return false }
            return next <= now
        }
    }

    /// One key per job and fingerprint, so an edited job notifies again.
    static func key(for job: BackupJob) -> String { "\(job.id.uuidString):\(job.fingerprint)" }

    /// The jobs whose key isn't in `alreadyNotified`.
    static func unnotified(_ jobs: [BackupJob], alreadyNotified: Set<String>) -> [BackupJob] {
        jobs.filter { !alreadyNotified.contains(key(for: $0)) }
    }

    static func request(for job: BackupJob) -> TransferNotificationRequest {
        TransferNotificationRequest(
            identifier: "backup-review-\(key(for: job))",
            title: String(localized: "Backup needs a preview"),
            body: String(localized: "\(job.name) needs a preview before it runs again."),
            backupID: job.id
        )
    }
}

/// The SMAppService status Nimbus cares about, so tests need no system call.
enum BackgroundAgentStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
}

/// Registers the backups agent. `SMAppService` in the app, a mock in tests.
@MainActor
protocol BackgroundAgentRegistering {
    var status: BackgroundAgentStatus { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

struct SMAppServiceAgent: BackgroundAgentRegistering {
    nonisolated static let plistName = "app.casavargas.nimbus.backups.plist"
    private let service = SMAppService.agent(plistName: Self.plistName)

    var status: BackgroundAgentStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// The Run Backups When Nimbus Is Closed switch.
@Observable
@MainActor
final class BackgroundBackupsService {
    /// Registered: on, or waiting for approval in Login Items.
    private(set) var isEnabled = false
    /// macOS wants the user to allow it in System Settings > Login Items.
    private(set) var needsApproval = false
    private(set) var lastError: String?

    @ObservationIgnored private let agent: any BackgroundAgentRegistering
    @ObservationIgnored private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "background-backups")

    init(agent: (any BackgroundAgentRegistering)? = nil, refreshOnInit: Bool = true) {
        self.agent = agent ?? SMAppServiceAgent()
        if refreshOnInit { refresh() }
    }

    func refresh() {
        lastError = nil
        apply(agent.status)
    }

    func register() {
        do {
            try agent.register()
            lastError = nil
            logger.info("Registered the backups agent")
        } catch {
            lastError = error.localizedDescription
            logger.error("Couldn't register the backups agent: \(error.localizedDescription)")
        }
        apply(agent.status)
    }

    func unregister() async {
        do {
            try await agent.unregister()
            lastError = nil
            logger.info("Unregistered the backups agent")
        } catch {
            lastError = error.localizedDescription
            logger.error("Couldn't unregister the backups agent: \(error.localizedDescription)")
        }
        apply(agent.status)
    }

    func openLoginItems() { agent.openSystemSettings() }

    private func apply(_ status: BackgroundAgentStatus) {
        isEnabled = status != .notRegistered
        needsApproval = status == .requiresApproval
    }
}
