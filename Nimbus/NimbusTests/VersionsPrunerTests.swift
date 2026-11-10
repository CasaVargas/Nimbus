import Foundation
import Testing
import RcloneKit
@testable import Nimbus

@Suite("VersionsPruner")
struct VersionsPrunerTests {
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let now = Date(timeIntervalSince1970: 1_794_171_600) // 2026-11-08 16:00:00 EST
    static let day: TimeInterval = 86_400

    static func stamp(daysAgo: Double) -> String {
        BackupRequest.stamp(for: now.addingTimeInterval(-daysAgo * day), timeZone: newYork)
    }

    static func job(
        destination: TransferEndpoint = .cloud(remote: "b2", path: "mac/Docs"),
        _ mutate: (inout BackupJob) -> Void = { _ in }
    ) -> BackupJob {
        var job = BackupJob.new(source: .local(path: "/Users/j/Docs"), destination: destination, now: now)
        job.versions.keep = .days30
        mutate(&job)
        return job
    }

    // MARK: - Which folders

    @Test func foreverPrunesNothing() {
        let names = [Self.stamp(daysAgo: 400), Self.stamp(daysAgo: 31)]
        #expect(VersionsPruner.foldersToPrune(names: names, keep: .forever, now: Self.now, timeZone: Self.newYork).isEmpty)
    }

    @Test func days30PrunesOlder() {
        // The cut-off is 31 days back: 30 days plus a day of grace.
        let old = Self.stamp(daysAgo: 32)
        let recent = Self.stamp(daysAgo: 29)
        #expect(old == "2026-10-07 170000")
        let pruned = VersionsPruner.foldersToPrune(names: [old, recent], keep: .days30, now: Self.now, timeZone: Self.newYork)
        #expect(pruned == [old])
    }

    @Test(arguments: [
        (BackupJob.Versions.Keep.days90, 92.0, 89.0),
        (BackupJob.Versions.Keep.year1, 367.0, 364.0),
    ])
    func longerKeepsPruneOlder(keep: BackupJob.Versions.Keep, olderDays: Double, newerDays: Double) {
        let old = Self.stamp(daysAgo: olderDays)
        let recent = Self.stamp(daysAgo: newerDays)
        let pruned = VersionsPruner.foldersToPrune(names: [recent, old], keep: keep, now: Self.now, timeZone: Self.newYork)
        #expect(pruned == [old])
    }

    @Test func cutOffIsThirtyOneCalendarDaysInTheTimeZone() {
        // 30 days and a day of grace before 2026-11-08 16:00 EST is 2026-10-08 16:00 EDT.
        let names = ["2026-10-08 160000", "2026-10-08 155959"]
        let pruned = VersionsPruner.foldersToPrune(names: names, keep: .days30, now: Self.now, timeZone: Self.newYork)
        #expect(pruned == ["2026-10-08 155959"])
    }

    // MARK: - Clock hardening

    @Test func aDayOfGraceOnTheCutOff() {
        // UTC, so no DST change in the window moves the calendar cut-off by an hour.
        let utc = TimeZone(identifier: "UTC")!
        func stamp(hoursAgo: Double) -> String {
            BackupRequest.stamp(for: Self.now.addingTimeInterval(-hoursAgo * 3600), timeZone: utc)
        }
        let recent = stamp(hoursAgo: 24)
        let inGrace = stamp(hoursAgo: 30 * 24 + 12)  // 30 days 12 hours
        let past = stamp(hoursAgo: 31 * 24 + 1)      // 31 days 1 hour
        let pruned = VersionsPruner.foldersToPrune(names: [recent, inGrace, past], keep: .days30,
                                                   now: Self.now, timeZone: utc)
        #expect(pruned == [past])
    }

    @Test func theNewestStampIsNeverPruned() {
        // Every stamp is past the cut-off (a clock set forward, say); the
        // newest stays, wherever the listing puts it.
        let names = [Self.stamp(daysAgo: 60), Self.stamp(daysAgo: 40), Self.stamp(daysAgo: 50)]
        for order in [names, names.reversed(), [names[1], names[0], names[2]], [names[2], names[1], names[0]]] {
            let pruned = VersionsPruner.foldersToPrune(names: order + ["notes"], keep: .days30,
                                                       now: Self.now, timeZone: Self.newYork)
            #expect(Set(pruned) == [names[0], names[2]], "\(order)")
            #expect(pruned == order.filter { $0 != names[1] }, "listing order is kept")
        }
    }

    @Test func aSingleStampPastTheCutOffIsKept() {
        let pruned = VersionsPruner.foldersToPrune(names: [Self.stamp(daysAgo: 400)], keep: .days30,
                                                   now: Self.now, timeZone: Self.newYork)
        #expect(pruned.isEmpty)
    }

    @Test func unparseableNamesIgnored() {
        let names = ["notes", "2026-13-40 999999", "", "2020-01-01", "2020-01-01 000000/x",
                     " 2020-01-01 000000", "2020-01-01 000000 copy", "2020-1-1 000000", ".", ".."]
        #expect(VersionsPruner.foldersToPrune(names: names, keep: .days30, now: Self.now, timeZone: Self.newYork).isEmpty)
    }

    @Test func stampsAreReadInTheGivenTimeZone() {
        // 17:00 in New York is an hour after the New York cut-off: kept.
        // Read as UTC, it is four hours before the UTC cut-off (21:00): pruned.
        let name = "2026-10-08 170000"
        let recent = "2026-11-07 120000"
        #expect(VersionsPruner.foldersToPrune(names: [name, recent], keep: .days30, now: Self.now,
                                              timeZone: Self.newYork).isEmpty)
        let utc = TimeZone(identifier: "UTC")!
        #expect(VersionsPruner.foldersToPrune(names: [name, recent], keep: .days30, now: Self.now,
                                              timeZone: utc) == [name])
    }

    // MARK: - The path handed to purge

    @Test func purgeTargetInsideCloudDestination() {
        let target = VersionsPruner.purgeTarget(job: Self.job(), stamp: "2026-10-08 160000")
        #expect(target == .init(fs: "b2:", remote: "mac/Docs/.nimbus-versions/2026-10-08 160000"))
    }

    @Test func purgeTargetInsideCloudRootDestination() {
        let job = Self.job(destination: .cloud(remote: "b2", path: ""))
        let target = VersionsPruner.purgeTarget(job: job, stamp: "2026-10-08 160000")
        #expect(target == .init(fs: "b2:", remote: ".nimbus-versions/2026-10-08 160000"))
    }

    @Test func purgeTargetCustomLocation() {
        let job = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "/old/Docs/")) }
        let target = VersionsPruner.purgeTarget(job: job, stamp: "2026-10-08 160000")
        #expect(target == .init(fs: "b2:", remote: "old/Docs/2026-10-08 160000"))
    }

    @Test func purgeTargetOnThisMac() {
        let job = Self.job(destination: .local(path: "/Volumes/Backup/Docs/"))
        let target = VersionsPruner.purgeTarget(job: job, stamp: "2026-10-08 160000")
        #expect(target == .init(fs: "/", remote: "Volumes/Backup/Docs/.nimbus-versions/2026-10-08 160000"))
    }

    @Test func purgeTargetIsNeverShorterThanAStampFolder() {
        let job = Self.job()
        for stamp in ["", "/", "notes", "..", "2026-13-40 999999", "2026-10-08 160000/..", "../2026-10-08 160000"] {
            #expect(VersionsPruner.purgeTarget(job: job, stamp: stamp) == nil, "stamp \(stamp)")
        }
    }

    @Test func purgeTargetRefusesUnsafeVersionsFolders() {
        let stamp = "2026-10-08 160000"
        let off = Self.job { $0.versions.enabled = false }
        let cloudRoot = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "")) }
        let slashes = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "//")) }
        let dots = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "old/../..")) }
        let emptyCloud = Self.job { $0.versions.location = .custom(.cloud(remote: "", path: "old")) }
        let macRoot = Self.job(destination: .local(path: "/Users/j/Backup")) {
            $0.versions.location = .custom(.local(path: "/"))
        }
        let relative = Self.job(destination: .local(path: "Backup"))
        for job in [off, cloudRoot, slashes, dots, emptyCloud, macRoot, relative] {
            #expect(VersionsPruner.purgeTarget(job: job, stamp: stamp) == nil, "\(job.versions) \(job.destination)")
        }
    }

    // MARK: - Pruning a job

    @Test func prunesByFolderNameNotFileDates() async {
        let client = MockBackupClient()
        let oldName = Self.stamp(daysAgo: 40)
        let newName = Self.stamp(daysAgo: 2)
        client.setListing(fs: "b2:", remote: "mac/Docs/.nimbus-versions", [
            // Moved in today, but the run that moved it was 40 days ago.
            BackupFixtures.listed(oldName, modTime: Self.now),
            // A two-year-old file removed two days ago.
            BackupFixtures.listed(newName, modTime: Self.now.addingTimeInterval(-730 * Self.day)),
        ])
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        #expect(outcome == .pruned([oldName]))
        #expect(client.purges == [.init(fs: "b2:", remote: "mac/Docs/.nimbus-versions/\(oldName)")])
    }

    @Test func filesNamedLikeStampsAreNotPurged() async {
        let client = MockBackupClient()
        let oldName = Self.stamp(daysAgo: 40)
        client.setListing(fs: "b2:", remote: "mac/Docs/.nimbus-versions", [
            BackupFixtures.listed(oldName, isDir: false),
        ])
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        #expect(outcome == .pruned([]))
        #expect(client.purges.isEmpty)
    }

    @Test func customLocationIsListedAndPurged() async {
        let client = MockBackupClient()
        let oldName = Self.stamp(daysAgo: 40)
        client.setListing(fs: "b2:", remote: "old/Docs", [BackupFixtures.listed(oldName), BackupFixtures.listed("keep me"),
                                                          BackupFixtures.listed(Self.stamp(daysAgo: 2))])
        let job = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "old/Docs")) }
        _ = await VersionsPruner.prune(job: job, client: client, now: Self.now, timeZone: Self.newYork)
        #expect(client.purges == [.init(fs: "b2:", remote: "old/Docs/\(oldName)")])
    }

    @Test func localVersionsGoThroughRclone() async {
        let client = MockBackupClient()
        let oldName = Self.stamp(daysAgo: 40)
        client.setListing(fs: "/", remote: "Volumes/Backup/Docs/.nimbus-versions",
                          [BackupFixtures.listed(oldName), BackupFixtures.listed(Self.stamp(daysAgo: 2))])
        let job = Self.job(destination: .local(path: "/Volumes/Backup/Docs"))
        _ = await VersionsPruner.prune(job: job, client: client, now: Self.now, timeZone: Self.newYork)
        #expect(client.purges == [.init(fs: "/", remote: "Volumes/Backup/Docs/.nimbus-versions/\(oldName)")])
    }

    @Test func versionsOffOrForeverDoesNotList() async {
        let client = MockBackupClient()
        let off = Self.job { $0.versions.enabled = false }
        let forever = Self.job { $0.versions.keep = .forever }
        #expect(await VersionsPruner.prune(job: off, client: client, now: Self.now, timeZone: Self.newYork) == .skipped)
        #expect(await VersionsPruner.prune(job: forever, client: client, now: Self.now, timeZone: Self.newYork) == .skipped)
        #expect(client.listCalls.isEmpty)
        #expect(client.purges.isEmpty)
    }

    @Test func emptyVersionsPathDoesNotList() async {
        let client = MockBackupClient()
        let job = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "")) }
        #expect(await VersionsPruner.prune(job: job, client: client, now: Self.now, timeZone: Self.newYork) == .skipped)
        #expect(client.listCalls.isEmpty)
    }

    @Test func listingFailurePurgesNothing() async {
        let client = MockBackupClient()
        client.failLists(with: URLError(.timedOut))
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        guard case .failed = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(client.purges.isEmpty)
    }

    @Test func purgeFailureStopsPruning() async {
        let client = MockBackupClient()
        client.setListing(fs: "b2:", remote: "mac/Docs/.nimbus-versions",
                          [BackupFixtures.listed(Self.stamp(daysAgo: 50)), BackupFixtures.listed(Self.stamp(daysAgo: 40))])
        client.failPurges(with: URLError(.timedOut))
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        guard case .failed = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
    }

    @MainActor final class Answers {
        var asked: [String] = []
        var allowed: Int
        init(allowed: Int) { self.allowed = allowed }
        func next(_ stamp: String) -> Bool {
            asked.append(stamp)
            return asked.count <= allowed
        }
    }

    @Test @MainActor func stopsWhenNoLongerAllowedToPurge() async {
        let client = MockBackupClient()
        let names = [Self.stamp(daysAgo: 50), Self.stamp(daysAgo: 45), Self.stamp(daysAgo: 40), Self.stamp(daysAgo: 2)]
        client.setListing(fs: "b2:", remote: "mac/Docs/.nimbus-versions", names.map { BackupFixtures.listed($0) })
        let none = Answers(allowed: 0)
        #expect(await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork,
                                           mayPurge: { none.next($0) }) == .stopped([]))
        #expect(none.asked == [names[0]])
        #expect(client.purges.isEmpty)

        let one = Answers(allowed: 1)
        #expect(await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork,
                                           mayPurge: { one.next($0) }) == .stopped([names[0]]))
        #expect(one.asked == [names[0], names[1]])
        #expect(client.purges == [.init(fs: "b2:", remote: "mac/Docs/.nimbus-versions/\(names[0])")])
    }

    // MARK: - Keep for and approval

    @Test func changingKeepForKeepsApproval() {
        var job = Self.job()
        job.approvedFingerprint = job.fingerprint
        for keep in [BackupJob.Versions.Keep.forever, .days90, .year1, .days30] {
            job.versions.keep = keep
            #expect(job.isApproved)
        }
    }

    // MARK: - Show Versions

    @Test func showVersionsInCloud() {
        #expect(VersionsReveal.target(for: Self.job(), versionsFolderExists: false)
            == .browse(cloud: "b2", path: "mac/Docs/.nimbus-versions"))
        let custom = Self.job { $0.versions.location = .custom(.cloud(remote: "b2", path: "/old/Docs/")) }
        #expect(VersionsReveal.target(for: custom, versionsFolderExists: true) == .browse(cloud: "b2", path: "old/Docs"))
    }

    @Test func showVersionsOnThisMacOpensTheFolder() {
        let job = Self.job(destination: .local(path: "/Volumes/Backup/Docs"))
        #expect(VersionsReveal.target(for: job, versionsFolderExists: true)
            == .open(URL(fileURLWithPath: "/Volumes/Backup/Docs/.nimbus-versions", isDirectory: true)))
    }

    @Test func showVersionsOnThisMacBeforeAnyRevealsTheDestination() {
        let job = Self.job(destination: .local(path: "/Volumes/Backup/Docs"))
        #expect(VersionsReveal.target(for: job, versionsFolderExists: false)
            == .reveal(URL(fileURLWithPath: "/Volumes/Backup/Docs", isDirectory: true)))
    }

    @Test func showVersionsUnavailableWhenOff() {
        let job = Self.job { $0.versions.enabled = false }
        #expect(VersionsReveal.target(for: job, versionsFolderExists: true) == .unavailable)
        #expect(VersionsReveal.target(for: job, versionsFolderExists: false) == .unavailable)
    }

    // MARK: - Jobs sharing a versions folder

    static func sharing(_ keep: BackupJob.Versions.Keep, folder: String = "old/Docs",
                        destination: String = "mac/A") -> BackupJob {
        job(destination: .cloud(remote: "b2", path: destination)) {
            $0.versions.location = .custom(.cloud(remote: "b2", path: folder))
            $0.versions.keep = keep
        }
    }

    @Test func sharedFolderKeepsTheLongest() {
        let short = Self.sharing(.days30, destination: "mac/A")
        let long = Self.sharing(.year1, destination: "mac/B")
        #expect(VersionsPruner.effectiveKeep(for: short, among: [short, long]) == .year1)
        #expect(VersionsPruner.effectiveKeep(for: long, among: [short, long]) == .year1)
    }

    @Test func sharedFolderWithForeverPrunesNothing() {
        let short = Self.sharing(.days30, destination: "mac/A")
        let forever = Self.sharing(.forever, destination: "mac/B")
        #expect(VersionsPruner.effectiveKeep(for: short, among: [short, forever]) == .forever)
    }

    @Test func sharedFolderMatchesAfterTrimmingSlashes() {
        let short = Self.sharing(.days30, folder: "old/Docs", destination: "mac/A")
        let long = Self.sharing(.days90, folder: "/old/Docs/", destination: "mac/B")
        #expect(VersionsPruner.effectiveKeep(for: short, among: [short, long]) == .days90)
    }

    @Test func unsharedFolderUsesItsOwnKeep() {
        let mine = Self.sharing(.days30, folder: "old/A", destination: "mac/A")
        let other = Self.sharing(.forever, folder: "old/B", destination: "mac/B")
        let insideOther = Self.job(destination: .cloud(remote: "b2", path: "old/A")) { $0.versions.keep = .forever }
        #expect(VersionsPruner.effectiveKeep(for: mine, among: [mine, other, insideOther]) == .days30)
    }

    @Test func versionsOffDoesNotCountAsSharing() {
        let mine = Self.sharing(.days30, destination: "mac/A")
        let off = Self.sharing(.forever, destination: "mac/B").with { $0.versions.enabled = false }
        #expect(VersionsPruner.effectiveKeep(for: mine, among: [mine, off]) == .days30)
    }

    @Test func pruneUsesTheKeepItIsGiven() async {
        let client = MockBackupClient()
        let name = Self.stamp(daysAgo: 40)
        client.setListing(fs: "b2:", remote: "mac/Docs/.nimbus-versions", [BackupFixtures.listed(name)])
        let outcome = await VersionsPruner.prune(job: Self.job(), keep: .days90, client: client,
                                                 now: Self.now, timeZone: Self.newYork)
        #expect(outcome == .pruned([]))
        #expect(await VersionsPruner.prune(job: Self.job(), keep: .forever, client: client,
                                           now: Self.now, timeZone: Self.newYork) == .skipped)
        #expect(client.purges.isEmpty)
    }

    // MARK: - First prune, before any versions exist

    @Test func notFoundListingIsNothingToPrune() async {
        let client = MockBackupClient()
        client.failLists(with: RcloneError.requestFailed(status: 404, message: "directory not found"))
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        #expect(outcome == .noVersionsYet)
        #expect(client.purges.isEmpty)
    }

    @Test func otherListingFailureStillFails() async {
        let client = MockBackupClient()
        client.failLists(with: RcloneError.requestFailed(status: 500, message: "couldn't list: permission denied"))
        let outcome = await VersionsPruner.prune(job: Self.job(), client: client, now: Self.now, timeZone: Self.newYork)
        #expect(outcome == .failed("Request failed (500): couldn't list: permission denied"))
        #expect(client.purges.isEmpty)
    }
}

private extension BackupJob {
    func with(_ mutate: (inout BackupJob) -> Void) -> BackupJob {
        var copy = self
        mutate(&copy)
        return copy
    }
}
