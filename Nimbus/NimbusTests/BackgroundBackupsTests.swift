import Foundation
import Testing
@testable import Nimbus

struct BackgroundLaunchTests {
    @Test func detectsTheAgentArgument() {
        #expect(BackgroundLaunch.isBackgroundLaunch(arguments: ["/Applications/Nimbus.app/Contents/MacOS/Nimbus", "--background-backups"]))
        #expect(!BackgroundLaunch.isBackgroundLaunch(arguments: ["/Applications/Nimbus.app/Contents/MacOS/Nimbus"]))
    }

    @Test func agentPlistRunsTheBackgroundLaunch() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LaunchAgents/\(SMAppServiceAgent.plistName)")
        let data = try Data(contentsOf: url)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "app.casavargas.nimbus.backups")
        #expect(plist["StartInterval"] as? Int == 900)
        let args = try #require(plist["ProgramArguments"] as? [String])
        let script = try #require(args.last)
        #expect(script.contains("lsappinfo find bundleid=app.casavargas.nimbus"))
        #expect(script.contains("open -g -j -b app.casavargas.nimbus --args \(BackgroundLaunch.argument)"))
    }
}

struct BackgroundQuitDecisionTests {
    private func decide(
        background: Bool = true, tookOver: Bool = false, started: Bool = true,
        catchUp: Bool = false, busy: Bool = false, elapsed: TimeInterval = 120
    ) -> Bool {
        BackgroundQuitDecision.shouldQuit(
            isBackgroundLaunch: background, userTookOver: tookOver, schedulerStarted: started,
            isCatchUpPending: catchUp, isBackupBusy: busy, elapsed: elapsed)
    }

    @Test func backgroundLaunchQuitsWhenIdle() { #expect(decide()) }
    @Test func userLaunchNeverQuits() { #expect(!decide(background: false)) }
    @Test func takenOverNeverQuits() { #expect(!decide(tookOver: true)) }
    @Test func waitsForCatchUp() { #expect(!decide(catchUp: true)) }
    @Test func waitsForRunningBackup() { #expect(!decide(busy: true)) }

    @Test func waitsForDaemonUntilDeadline() {
        #expect(!decide(started: false, elapsed: 60))
        #expect(decide(started: false, elapsed: BackgroundQuitDecision.startDeadline))
    }
}

struct BackupReviewNoticesTests {
    static let planner = BackupSchedulePlannerTests.planner
    static let now = BackupSchedulePlannerTests.date("2026-11-10T09:00:00-05:00")
    static let lastRun = BackupSchedulePlannerTests.date("2026-11-07T02:00:00-05:00")

    /// Approved once, then its mode changed.
    static func changedJob() -> BackupJob {
        var job = BackupSchedulePlannerTests.job(lastRunStart: lastRun)
        job.mode = job.mode == .mirror ? .addOnly : .mirror
        return job
    }

    @Test func dueApprovedJobRunsAndIsNoNotice() {
        let job = BackupSchedulePlannerTests.job(lastRunStart: Self.lastRun)
        #expect(Self.planner.dueJobs([job], now: Self.now, busy: []) == [job.id])
        #expect(BackupReviewNotices.jobsNeedingReview([job], planner: Self.planner, now: Self.now).isEmpty)
    }

    @Test func changedDueJobDoesNotRunAndNeedsReview() {
        let job = Self.changedJob()
        #expect(Self.planner.dueJobs([job], now: Self.now, busy: []).isEmpty)
        #expect(BackupReviewNotices.jobsNeedingReview([job], planner: Self.planner, now: Self.now).map(\.id) == [job.id])
    }

    @Test func stoppedAtLimitDoesNotRunAndNeedsNoNewNotice() {
        // The run that hit the limit already notified.
        let job = BackupSchedulePlannerTests.job(lastRunStart: Self.lastRun, outcome: .limitHit)
        #expect(job.isStoppedAtRemovalLimit)
        #expect(Self.planner.dueJobs([job], now: Self.now, busy: []).isEmpty)
        #expect(BackupReviewNotices.jobsNeedingReview([job], planner: Self.planner, now: Self.now).isEmpty)
    }

    @Test func pausedNeverApprovedAndNotDueAreLeftOut() {
        var paused = Self.changedJob()
        paused.isPaused = true
        var neverApproved = Self.changedJob()
        neverApproved.approvedFingerprint = nil
        let notDue = Self.changedJob()
        let early = BackupSchedulePlannerTests.date("2026-11-08T01:00:00-05:00")
        #expect(BackupReviewNotices.jobsNeedingReview([paused, neverApproved], planner: Self.planner, now: Self.now).isEmpty)
        #expect(BackupReviewNotices.jobsNeedingReview([notDue], planner: Self.planner, now: early).isEmpty)
    }

    @Test func notifiesOncePerFingerprint() {
        let job = Self.changedJob()
        let notified: Set<String> = [BackupReviewNotices.key(for: job)]
        #expect(BackupReviewNotices.unnotified([job], alreadyNotified: notified).isEmpty)
        var edited = job
        edited.mode = edited.mode == .mirror ? .addOnly : .mirror
        #expect(BackupReviewNotices.unnotified([edited], alreadyNotified: notified).map(\.id) == [job.id])
    }

    @Test func noticeOpensTheJob() {
        let job = Self.changedJob()
        #expect(BackupReviewNotices.request(for: job).backupID == job.id)
    }
}

@MainActor
final class MockBackgroundAgent: BackgroundAgentRegistering {
    var status: BackgroundAgentStatus = .notRegistered
    var statusAfterRegister: BackgroundAgentStatus = .enabled
    var registerError: (any Error)?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openedSettings = false

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() async throws {
        unregisterCalls += 1
        status = .notRegistered
    }

    func openSystemSettings() { openedSettings = true }
}

@MainActor
struct BackgroundBackupsServiceTests {
    struct Failure: LocalizedError { var errorDescription: String? { "Nope" } }

    @Test func registersAndUnregisters() async {
        let agent = MockBackgroundAgent()
        let service = BackgroundBackupsService(agent: agent)
        #expect(!service.isEnabled)
        service.register()
        #expect(service.isEnabled && agent.registerCalls == 1)
        await service.unregister()
        #expect(!service.isEnabled && agent.unregisterCalls == 1)
    }

    @Test func approvalNeededStaysOnWithCaption() {
        let agent = MockBackgroundAgent()
        agent.statusAfterRegister = .requiresApproval
        let service = BackgroundBackupsService(agent: agent)
        service.register()
        #expect(service.isEnabled && service.needsApproval)
        service.openLoginItems()
        #expect(agent.openedSettings)
    }

    @Test func registerFailureShowsError() {
        let agent = MockBackgroundAgent()
        agent.registerError = Failure()
        let service = BackgroundBackupsService(agent: agent)
        service.register()
        #expect(!service.isEnabled)
        #expect(service.lastError == "Nope")
    }
}

struct OpenAtLoginNoteRunsWhenClosedTests {
    @Test func hiddenWhenEitherSwitchIsOn() {
        let daily: [BackupSchedule] = [.daily(hour: 2, minute: 0)]
        #expect(OpenAtLoginNote.isShown(schedules: daily, openAtLoginIsOn: false, runsWhenClosed: false))
        #expect(!OpenAtLoginNote.isShown(schedules: daily, openAtLoginIsOn: true, runsWhenClosed: false))
        #expect(!OpenAtLoginNote.isShown(schedules: daily, openAtLoginIsOn: false, runsWhenClosed: true))
        #expect(!OpenAtLoginNote.isShown(schedules: [.manual], openAtLoginIsOn: false, runsWhenClosed: false))
    }
}
