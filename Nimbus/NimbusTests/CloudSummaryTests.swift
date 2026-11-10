import Testing
import Foundation
import RcloneKit
@testable import Nimbus

@Suite("CloudSummaryBuilder")
@MainActor
struct CloudSummaryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func remote(_ name: String, _ type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    func transfer(src: String, dst: String, eta: TimeInterval? = nil, progress: Double = 0.5,
                  status: TransferStatus = .active, op: TransferOperation = .copy,
                  completedAt: Date? = nil) -> Transfer {
        Transfer(jobID: 1, operation: op, srcFs: src, dstFs: dst, startedAt: now,
                 completedAt: completedAt, status: status, origin: .manual,
                 nimbusUUID: UUID(), progress: progress, eta: eta)
    }

    func build(
        _ remotes: [Remote],
        statuses: [String: RemoteStatus] = [:],
        quotas: [String: StorageQuota] = [:],
        transfers: [Transfer] = [],
        inFinder: Set<String>? = nil,
        lastConnected: [String: Date] = [:],
        dismissed: Set<String> = [],
        daemon: RcloneDaemon.Status = .connected
    ) -> CloudSummary {
        CloudSummaryBuilder.build(
            remotes: remotes, statuses: statuses, quotas: quotas,
            activeTransfers: transfers,
            isInFinder: { inFinder?.contains($0) ?? true },
            providerName: { $0 == "drive" ? "Google Drive" : $0 },
            lastConnected: lastConnected, dismissedSuggestions: dismissed,
            daemon: daemon, now: now
        )
    }

    // MARK: Status sentences

    @Test func connectedReadsReady() {
        let s = build([remote("Personal")], statuses: ["Personal": .connected])
        #expect(s.rows[0].health == .ready)
        #expect(s.rows[0].sentence == "Ready")
        #expect(s.rows[0].providerName == "Google Drive")
        #expect(s.overall == .allReady)
    }

    @Test func eachStatusMapsToPlainSentence() {
        let cases: [(RemoteStatus, CloudSummary.Health, String)] = [
            (.unknown, .checking, "Checking…"),
            (.authNeeded, .needsSignIn, "Needs sign-in"),
            (.unreachable(reason: "no route to host"), .unreachable, "Can't reach this server right now"),
            (.error(reason: "bad config"), .failing, "Can't connect"),
        ]
        for (status, health, sentence) in cases {
            let row = build([remote("A")], statuses: ["A": status]).rows[0]
            #expect(row.health == health)
            #expect(row.sentence == sentence)
        }
    }

    @Test func uploadsWinOverStatusAndCarryETA() {
        let s = build([remote("Dropbox", "dropbox")], statuses: ["Dropbox": .connected],
                      transfers: [transfer(src: "Personal:a", dst: "Dropbox:x", eta: 120),
                                  transfer(src: "Personal:b", dst: "Dropbox:y", eta: 30),
                                  transfer(src: "Personal:c", dst: "Dropbox:z")])
        #expect(s.rows[0].health == .busy)
        #expect(s.rows[0].sentence == "Uploading 3 items, 2 min left")
    }

    @Test func downloadSentenceWhenCloudIsSource() {
        let s = build([remote("Personal")], statuses: ["Personal": .connected],
                      transfers: [transfer(src: "Personal:a", dst: "Work:b")])
        #expect(s.rows[0].sentence == "Downloading 1 item")
    }

    @Test func remoteNamePrefixDoesNotMatchLongerName() {
        let s = build([remote("Drive"), remote("Drive2")],
                      statuses: ["Drive": .connected, "Drive2": .connected],
                      transfers: [transfer(src: "local:/x", dst: "Drive2:y")])
        #expect(s.rows[0].health == .ready)
        #expect(s.rows[1].health == .busy)
    }

    @Test func etaWording() {
        #expect(CloudSummaryBuilder.etaText(20) == "less than a minute")
        #expect(CloudSummaryBuilder.etaText(70) == "1 min")
        #expect(CloudSummaryBuilder.etaText(600) == "10 min")
        #expect(CloudSummaryBuilder.etaText(5400) == "about 2 hours")
    }

    // MARK: Overall + attention

    @Test func daemonStatesOverrideEverything() {
        #expect(build([remote("A")], daemon: .starting).overall == .starting)
        #expect(build([remote("A")], daemon: .error("boom")).overall == .engineDown("boom"))
        #expect(build([]).overall == .noClouds)
    }

    @Test func attentionPriorityIsSignInThenFailingThenUnreachable() {
        let remotes = [remote("N"), remote("F"), remote("S")]
        let s = build(remotes, statuses: ["N": .unreachable(reason: "x"), "F": .error(reason: "y"), "S": .authNeeded])
        #expect(s.attention?.id == "S")
        #expect(s.overall == .needsAttention(s.rows[2]))

        let s2 = build(remotes, statuses: ["N": .unreachable(reason: "x"), "F": .error(reason: "y"), "S": .connected])
        #expect(s2.attention?.id == "F")
    }

    @Test func recentlySeenUnreachableCloudGetsNoBanner() {
        let recent = now.addingTimeInterval(-3600)
        let old = now.addingTimeInterval(-3 * 24 * 3600)
        let s = build([remote("NAS", "sftp")], statuses: ["NAS": .unreachable(reason: "x")],
                      lastConnected: ["NAS": recent])
        #expect(s.attention == nil)
        #expect(s.rows[0].lastConnected == recent)
        let s2 = build([remote("NAS", "sftp")], statuses: ["NAS": .unreachable(reason: "x")],
                       lastConnected: ["NAS": old])
        #expect(s2.attention?.id == "NAS")
    }

    @Test func busyOverallNamesSingleDestination() {
        let s = build([remote("A"), remote("B")], statuses: ["A": .connected, "B": .connected],
                      transfers: [transfer(src: "A:x", dst: "B:x", progress: 0.2),
                                  transfer(src: "A:y", dst: "B:y", progress: 0.6)])
        guard case .busy(let busy) = s.overall else { Issue.record("expected busy"); return }
        #expect(busy.sentence == "Copying 2 items to B")
        #expect(abs(busy.progress - 0.4) < 0.0001)
    }

    // MARK: Bar math

    @Test func barMathMixesLimitedAndPayAsYouGo() {
        let s = build(
            [remote("P"), remote("B2", "b2"), remote("NAS", "sftp")],
            statuses: ["P": .connected, "B2": .connected, "NAS": .unreachable(reason: "x")],
            quotas: ["P": StorageQuota(used: 1_200, total: 2_000),
                     "B2": StorageQuota(used: 700, total: nil)]
        )
        #expect(s.usedBytes == 1_900)
        #expect(s.freeBytes == 800)
        #expect(s.capacityBytes == 2_700)
    }

    @Test func freeIsNilWhenNoCloudReportsALimit() {
        let s = build([remote("B2", "b2")], statuses: ["B2": .connected],
                      quotas: ["B2": StorageQuota(used: 700, total: nil)])
        #expect(s.freeBytes == nil)
        #expect(s.capacityBytes == 700)
    }

    @Test func tintsFollowSidebarOrderAndClampToLastSlot() {
        let remotes = (0..<10).map { remote("R\($0)") }
        let tints = build(remotes).rows.map(\.tint)
        #expect(tints == [0, 1, 2, 3, 4, 5, 6, 7, 7, 7])
    }

    // MARK: Suggestions

    @Test func suggestsNearlyFullAndNotInFinderRespectingDismissals() {
        let remotes = [remote("Full"), remote("Hidden")]
        let s = build(remotes, statuses: ["Full": .connected, "Hidden": .connected],
                      quotas: ["Full": StorageQuota(used: 95, total: 100)],
                      inFinder: ["Full"])
        #expect(s.suggestions.map(\.id) == ["full:Full", "finder:Hidden"])
        let s2 = build(remotes, statuses: ["Full": .connected, "Hidden": .connected],
                       quotas: ["Full": StorageQuota(used: 95, total: 100)],
                       inFinder: ["Full"], dismissed: ["finder:Hidden"])
        #expect(s2.suggestions.map(\.id) == ["full:Full"])
    }

    // MARK: Activity

    @Test func activityLinesWordFinishedTransfersNewestFirst() {
        let lines = ActivityLine.lines(from: [
            transfer(src: "Personal:Photos/Yosemite 2026", dst: "Archive:", status: .completed,
                     completedAt: now.addingTimeInterval(-100)),
            transfer(src: "Personal:", dst: "Dropbox:Backup", status: .failed("x"), op: .sync,
                     completedAt: now),
            transfer(src: "A:x", dst: "B:", status: .cancelled, completedAt: now),
        ])
        #expect(lines.map(\.text) == ["Couldn't sync Personal to Dropbox",
                                      "Copied Yosemite 2026 to Archive"])
        #expect(lines[0].isFailure)
        #expect(lines[1].route == .cloud("Archive"))
        #expect(lines[0].route == .cloud("Dropbox"))
    }
    // MARK: Aliases

    @Test func aliasResolvesToTargetBackendAndStopsOnCycles() {
        let gdrive = Remote(name: "gdrive", type: "drive", config: [:])
        let personal = Remote(name: "Personal Drive", type: "alias", config: ["remote": "gdrive:Personal"])
        let local = Remote(name: "Desk", type: "alias", config: ["remote": "/Users/me/Desktop"])
        let loopA = Remote(name: "A", type: "alias", config: ["remote": "B:"])
        let loopB = Remote(name: "B", type: "alias", config: ["remote": "A:"])
        let all = [gdrive, personal, local, loopA, loopB]
        #expect(CloudNaming.resolvedType(of: personal, in: all) == "drive")
        #expect(CloudNaming.resolvedType(of: local, in: all) == "alias")
        #expect(CloudNaming.resolvedType(of: loopA, in: all) == "alias")

        let s = CloudSummaryBuilder.build(
            remotes: [gdrive, personal], statuses: [:], quotas: [:], activeTransfers: [],
            isInFinder: { _ in true }, providerName: { $0 == "drive" ? "Google Drive" : $0 },
            lastConnected: [:], dismissedSuggestions: [], daemon: .connected, now: now,
            resolveType: { CloudNaming.resolvedType(of: $0, in: [gdrive, personal]) }
        )
        #expect(s.rows[1].providerType == "drive")
        #expect(s.rows[1].providerName == "Google Drive")
    }

    // MARK: Backups

    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func job(
        _ schedule: BackupSchedule = .daily(hour: 3, minute: 0), name: String = "Documents to B2",
        lastRun: (start: Date, outcome: BackupRunSummary.Outcome)? = nil
    ) -> BackupJob {
        var j = BackupJob.new(source: .local(path: "/Users/me/Documents"),
                              destination: .cloud(remote: "B2", path: "docs"), now: at(1, 9))
        j.name = name
        j.schedule = schedule
        j.approvedFingerprint = j.fingerprint
        j.approvedAt = at(1, 9)
        if let lastRun {
            j.lastRun = BackupRunSummary(startedAt: lastRun.start, finishedAt: lastRun.start.addingTimeInterval(60),
                                         trigger: .scheduled, outcome: lastRun.outcome,
                                         copied: 0, replaced: 0, removed: 0, errors: 0, bytes: 0)
        }
        return j
    }

    func suggestions(_ jobs: [BackupJob], now: Date) -> [String] {
        BackupSuggestions.notes(for: jobs, now: now, calendar: cal).map(\.sentence)
    }

    func backupTransfer(_ title: String, status: TransferStatus, outcome: BackupRunSummary.Outcome? = nil,
                        dstFs: String = "B2:docs", backupID: UUID = UUID()) -> Transfer {
        var t = Transfer(jobID: 1, operation: .sync, srcFs: "/Users/me/Documents", dstFs: dstFs,
                         startedAt: now, completedAt: now, status: status, origin: .backup, nimbusUUID: UUID())
        t.backup = .init(backupID: backupID, title: title, trigger: .scheduled,
                         isMirrorWithVersions: false, hadRemovalLimit: true)
        if let outcome {
            t.summary = BackupRunSummary(startedAt: now, finishedAt: now, trigger: .scheduled, outcome: outcome,
                                         copied: 0, replaced: 0, removed: 0, errors: 0, bytes: 0)
        }
        return t
    }

    @Test func activityLineForBackup() {
        let lines = ActivityLine.lines(from: [
            backupTransfer("Documents to B2", status: .completed),
        ])
        #expect(lines.map(\.text) == ["Backed up Documents to B2"])
        #expect(lines[0].isFailure == false)
    }

    @Test func backupActivityFailureComesFromTheRunNotTheText() {
        let completed = ActivityLine.lines(from: [backupTransfer("Photos failed", status: .completed)])
        #expect(completed.map(\.text) == ["Backed up Photos failed"])
        #expect(completed[0].isFailure == false)
        let stopped = ActivityLine.lines(from: [backupTransfer("Photos", status: .failed("max-delete"), outcome: .limitHit)])
        #expect(stopped[0].isFailure)
        let failed = ActivityLine.lines(from: [backupTransfer("Photos", status: .failed("boom"))])
        #expect(failed[0].isFailure)
    }

    @Test func backupActivityOpensBackupsOnThatJob() {
        let id = UUID()
        let toCloud = ActivityLine.lines(from: [backupTransfer("Documents to B2", status: .completed, backupID: id)])
        #expect(toCloud[0].route == .backups(id))
        let onThisMac = ActivityLine.lines(from: [
            backupTransfer("Documents", status: .failed("boom"), dstFs: "/Volumes/Backup/Documents", backupID: id)])
        #expect(onThisMac[0].route == .backups(id))
    }

    @Test func activityLineForFailedStoppedAndCancelledBackups() {
        let failed = ActivityLine.lines(from: [backupTransfer("Documents to B2", status: .failed("boom"))])
        #expect(failed.map(\.text) == ["Backup Documents to B2 failed"])
        #expect(failed[0].isFailure)
        let stopped = ActivityLine.lines(from: [
            backupTransfer("Documents to B2", status: .failed("max-delete"), outcome: .limitHit)])
        #expect(stopped.map(\.text) == ["Backup Documents to B2 stopped"])
        #expect(ActivityLine.lines(from: [backupTransfer("Documents to B2", status: .cancelled)]).isEmpty)
    }

    @Test func overdueSuggestion() {
        // Daily 2:00 AM; last run started at the slot, three days ago.
        let j = job(.daily(hour: 2, minute: 0), lastRun: (at(4, 2), .completed))
        #expect(suggestions([j], now: at(7, 3)) == ["Documents to B2 hasn't run in 3 days"])
        let s = build([remote("B2")], statuses: [:], dismissed: [])
        #expect(s.suggestions.allSatisfy { if case .backup = $0 { false } else { true } })
    }

    @Test func overdueNeedsThreeMissedSlots() {
        let j = job(.daily(hour: 2, minute: 0), lastRun: (at(4, 2), .completed))
        #expect(suggestions([j], now: at(6, 3)).isEmpty)          // two slots missed
        #expect(suggestions([j], now: at(7, 1, 59)).isEmpty)      // third slot not yet
        #expect(suggestions([j], now: at(7, 2)).count == 1)       // exactly three
    }

    @Test func overdueReadsInHoursUnderADayAndSingularForms() {
        let hourly = job(.hourly, lastRun: (at(7, 8, 30), .completed))
        #expect(suggestions([hourly], now: at(7, 12, 30)) == ["Documents to B2 hasn't run in 4 hours"])
        #expect(BackupSuggestions.elapsed(since: at(7, 8), now: at(7, 9, 10), calendar: cal) == "1 hour")
        #expect(BackupSuggestions.elapsed(since: at(6, 8), now: at(7, 9, 10), calendar: cal) == "1 day")
    }

    @Test func neverRunJobCountsFromItsAnchor() {
        let j = job()   // approved at the 1st, 09:00
        #expect(suggestions([j], now: at(5, 4)) == ["Documents to B2 hasn't run in 3 days"])
    }

    @Test func pausedJobNeverSuggested() {
        var paused = job(lastRun: (at(4, 2, 30), .failed("x")))
        paused.isPaused = true
        #expect(suggestions([paused], now: at(7, 3, 30)).isEmpty)
        var unapproved = job(lastRun: (at(4, 2, 30), .completed))
        unapproved.approvedFingerprint = nil
        #expect(suggestions([unapproved], now: at(7, 3, 30)).isEmpty)
        #expect(suggestions([job(.manual, lastRun: (at(4, 2, 30), .failed("x")))], now: at(7, 3, 30)).isEmpty)
    }

    @Test func failedLastNightSuggestion() {
        let j = job(lastRun: (at(7, 3), .failed("no route")))
        #expect(suggestions([j], now: at(7, 9)) == ["Documents to B2 failed last night"])
    }

    @Test func lastNightRunsFromSixPMToSixAM() {
        let now = at(7, 9)
        #expect(BackupSuggestions.when(at(6, 18), now: now, calendar: cal) == "last night")
        #expect(BackupSuggestions.when(at(6, 17, 59), now: now, calendar: cal) == "yesterday")
        #expect(BackupSuggestions.when(at(7, 5, 59), now: now, calendar: cal) == "last night")
        #expect(BackupSuggestions.when(at(7, 6), now: now, calendar: cal) == "today")
        #expect(BackupSuggestions.when(at(4, 20), now: now, calendar: cal) == "3 days ago")
    }

    @Test func failedRunStopsBeingSuggestedAfterSevenDays() {
        let j = job(.weekly(weekday: 2, hour: 3, minute: 0), lastRun: (at(1, 3), .failed("x")))
        #expect(suggestions([j], now: at(8, 2)) == ["Documents to B2 failed 7 days ago"])
        #expect(suggestions([j], now: at(8, 4)).isEmpty)
    }

    @Test func cancelledRunIsNotSuggested() {
        #expect(suggestions([job(lastRun: (at(7, 3), .cancelled))], now: at(7, 9)).isEmpty)
    }

    @Test func stoppedSuggestionHasNoCutOffAndBeatsFailed() {
        let j = job(lastRun: (at(7, 3), .limitHit))
        #expect(suggestions([j], now: at(7, 9)) == ["Documents to B2 stopped last night"])
        let old = job(lastRun: (at(1, 12), .limitHit))
        #expect(suggestions([old], now: at(20, 9)) == ["Documents to B2 stopped 19 days ago"])
        var approved = old
        approved.approvedAt = at(2, 9)
        #expect(suggestions([approved], now: at(2, 10)).isEmpty)
    }

    @Test func failedBeatsOverdueAndOneNotePerJob() {
        let j = job(lastRun: (at(4, 2, 30), .failed("x")))
        #expect(suggestions([j], now: at(7, 3, 30)) == ["Documents to B2 failed 3 days ago"])
    }

    // MARK: Backups the runner or scheduler is about to deal with

    func notes(_ jobs: [BackupJob], now: Date, busy: Set<UUID> = [], catchUpPending: Bool = false) -> [String] {
        BackupSuggestions.notes(for: jobs, now: now, calendar: cal, busy: busy, catchUpPending: catchUpPending)
            .map(\.sentence)
    }

    @Test func busyJobWithFailedRunGetsNoNote() {
        let j = job(lastRun: (at(7, 3), .failed("no route")))
        #expect(notes([j], now: at(7, 9)) == ["Documents to B2 failed last night"])
        #expect(notes([j], now: at(7, 9), busy: [j.id]).isEmpty)
    }

    @Test func busyOverdueJobGetsNoNote() {
        let j = job(.daily(hour: 2, minute: 0), lastRun: (at(4, 2), .completed))
        #expect(notes([j], now: at(7, 3), busy: [j.id]).isEmpty)
    }

    @Test func busyStoppedJobGetsNoNote() {
        let j = job(lastRun: (at(7, 3), .limitHit))
        #expect(notes([j], now: at(7, 9), busy: [j.id]).isEmpty)
    }

    @Test func overdueJobWithCatchUpPendingGetsNoNote() {
        let j = job(.daily(hour: 2, minute: 0), lastRun: (at(4, 2), .completed))
        #expect(notes([j], now: at(7, 3), catchUpPending: true).isEmpty)
    }

    @Test func overdueJobNotBusyNothingPendingHasntRun() {
        let j = job(.daily(hour: 2, minute: 0), lastRun: (at(4, 2), .completed))
        let other = job(name: "Photos to B2")
        #expect(notes([j], now: at(7, 3), busy: [other.id], catchUpPending: false)
            == ["Documents to B2 hasn't run in 3 days"])
    }

    @Test func failedAndStoppedJobsStillShowWithCatchUpPending() {
        let failed = job(lastRun: (at(7, 3), .failed("no route")))
        let stopped = job(name: "Photos to B2", lastRun: (at(7, 3), .limitHit))
        #expect(Set(notes([failed, stopped], now: at(7, 9), catchUpPending: true))
            == ["Documents to B2 failed last night", "Photos to B2 stopped last night"])
    }

    @Test func buildPassesBusyAndPendingToBackupNotes() {
        let failed = job(lastRun: (at(7, 3), .failed("x")))
        let overdue = job(.daily(hour: 2, minute: 0), name: "Photos to B2", lastRun: (at(4, 2), .completed))
        func backupNotes(busy: Set<UUID>, pending: Bool) -> [UUID] {
            CloudSummaryBuilder.build(
                remotes: [], statuses: [:], quotas: [:], activeTransfers: [], isInFinder: { _ in true },
                providerName: { $0 }, lastConnected: [:], dismissedSuggestions: [], daemon: .connected,
                now: at(7, 9), backups: [failed, overdue], busyBackups: busy, backupCatchUpPending: pending,
                calendar: cal
            ).suggestions.compactMap { if case .backup(let note) = $0 { note.jobID } else { nil } }
        }
        #expect(Set(backupNotes(busy: [], pending: false)) == [failed.id, overdue.id])
        #expect(backupNotes(busy: [failed.id], pending: false) == [overdue.id])
        #expect(backupNotes(busy: [], pending: true) == [failed.id])
    }

    @Test func notesAreOrderedStoppedFailedHasntRun() {
        let overdue = job(.daily(hour: 2, minute: 0), name: "Music to B2", lastRun: (at(4, 2), .completed))
        let failed = job(name: "Photos to B2", lastRun: (at(7, 3), .failed("x")))
        let failedToo = job(name: "Mail to B2", lastRun: (at(7, 4), .failed("x")))
        let stopped = job(name: "Docs to B2", lastRun: (at(7, 3), .limitHit))
        #expect(suggestions([overdue, failed, failedToo, stopped], now: at(7, 9)) == [
            "Docs to B2 stopped last night",
            "Photos to B2 failed last night",
            "Mail to B2 failed last night",
            "Music to B2 hasn't run in 3 days",
        ])
        // Home shows two: the stopped job, which never runs again on its own, isn't hidden.
        let s = CloudSummaryBuilder.build(
            remotes: [], statuses: [:], quotas: [:], activeTransfers: [], isInFinder: { _ in true },
            providerName: { $0 }, lastConnected: [:], dismissedSuggestions: [], daemon: .connected,
            now: at(7, 9), backups: [overdue, failed, failedToo, stopped], calendar: cal)
        #expect(s.suggestions.map(\.id).count == 2)
        guard case .backup(let first) = s.suggestions.first else { Issue.record("no backup note"); return }
        #expect(first.jobID == stopped.id)
    }

    @Test func backupSuggestionsComeFirstAndOpenBackups() {
        let j = job(lastRun: (at(7, 3), .failed("x")))
        let s = CloudSummaryBuilder.build(
            remotes: [remote("Personal")], statuses: ["Personal": .connected],
            quotas: [:], activeTransfers: [], isInFinder: { _ in false }, providerName: { $0 },
            lastConnected: [:], dismissedSuggestions: [], daemon: .connected, now: at(7, 9),
            backups: [j], calendar: cal)
        guard case .backup(let note) = s.suggestions.first else { Issue.record("no backup note"); return }
        #expect(note.jobID == j.id)
        #expect(s.suggestions.count == 2)
        let dismissed = CloudSummaryBuilder.build(
            remotes: [remote("Personal")], statuses: ["Personal": .connected],
            quotas: [:], activeTransfers: [], isInFinder: { _ in true }, providerName: { $0 },
            lastConnected: [:], dismissedSuggestions: [note.dismissKey], daemon: .connected, now: at(7, 9),
            backups: [j], calendar: cal)
        #expect(dismissed.suggestions.isEmpty)
    }
}
