import Foundation
import Testing
@testable import Nimbus

struct BackupJobTests {
    static let source = TransferEndpoint.local(path: "/Users/j/Documents")
    static let destination = TransferEndpoint.cloud(remote: "b2", path: "mac/Docs")
    static let created = Date(timeIntervalSince1970: 1_794_000_000)

    static func job() -> BackupJob {
        BackupJob.new(source: source, destination: destination, now: created)
    }

    static var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    static func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }

    // MARK: - Defaults

    @Test func newJobDefaults() {
        let job = Self.job()
        #expect(job.name == "Documents to b2")
        #expect(job.source == Self.source)
        #expect(job.destination == Self.destination)
        #expect(job.mode == .mirror)
        #expect(job.versions == BackupJob.Versions(enabled: true, location: .insideDestination, keep: .forever))
        #expect(job.removalLimit == 100)
        #expect(job.excludes == [".DS_Store", "._*", ".Trash/**", ".Spotlight-V100/**"])
        #expect(job.excludes == BackupJob.macJunkExcludes)
        #expect(job.schedule == .manual)
        #expect(job.isPaused == false)
        #expect(job.approvedFingerprint == nil)
        #expect(job.approvedAt == nil)
        #expect(job.lastRun == nil)
        #expect(job.createdAt == Self.created)
        #expect(job.isApproved == false)
    }

    @Test func localDestinationNameUsesFolderName() {
        let job = BackupJob.new(source: Self.destination, destination: .local(path: "/Volumes/Backup/Docs"), now: Self.created)
        #expect(job.name == "Docs to Docs")
    }

    // MARK: - Fingerprint

    enum Field: String, CaseIterable { case source, destination, mode, excludes, versionsEnabled, versionsLocation, removalLimit }

    @Test(arguments: Field.allCases)
    func fingerprintChangesFor(field: Field) {
        let original = Self.job()
        var edited = original
        switch field {
        case .source: edited.source = .local(path: "/Users/j/Desktop")
        case .destination: edited.destination = .cloud(remote: "b2", path: "other")
        case .mode: edited.mode = .addOnly
        case .excludes: edited.excludes.append("*.tmp")
        case .versionsEnabled: edited.versions.enabled = false
        case .versionsLocation: edited.versions.location = .custom(.cloud(remote: "b2", path: "old"))
        case .removalLimit: edited.removalLimit = 50
        }
        #expect(edited.fingerprint != original.fingerprint)
    }

    @Test func fingerprintIgnoresNameScheduleAndPause() {
        let original = Self.job()
        var edited = original
        edited.name = "Renamed"
        edited.schedule = .daily(hour: 2, minute: 0)
        edited.isPaused = true
        edited.versions.keep = .days30
        #expect(edited.fingerprint == original.fingerprint)
    }

    @Test func fingerprintIsLowercaseHexSHA256() {
        let fingerprint = Self.job().fingerprint
        #expect(fingerprint.count == 64)
        #expect(fingerprint.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func approvalClearsWhenFingerprintChanges() {
        var job = Self.job()
        job.approvedFingerprint = job.fingerprint
        #expect(job.isApproved)
        job.name = "Still approved"
        #expect(job.isApproved)
        job.excludes.append("*.tmp")
        #expect(job.isApproved == false)
    }

    // MARK: - Versions

    @Test func versionsEndpointInsideDestination() {
        #expect(Self.job().versionsEndpoint == .cloud(remote: "b2", path: "mac/Docs/.nimbus-versions"))
    }

    @Test func versionsEndpointCustomAndOff() {
        var job = Self.job()
        job.versions.location = .custom(.cloud(remote: "b2", path: "old"))
        #expect(job.versionsEndpoint == .cloud(remote: "b2", path: "old"))
        job.versions.enabled = false
        #expect(job.versionsEndpoint == nil)
    }

    // MARK: - Schedule

    @Test func dailyNextRun() {
        let schedule = BackupSchedule.daily(hour: 2, minute: 0)
        #expect(schedule.nextRun(after: Self.date("2026-11-08T01:00:00-05:00"), calendar: Self.newYork)
            == Self.date("2026-11-08T02:00:00-05:00"))
        #expect(schedule.nextRun(after: Self.date("2026-11-08T02:00:00-05:00"), calendar: Self.newYork)
            == Self.date("2026-11-09T02:00:00-05:00"))
    }

    @Test func hourlyNextRun() {
        #expect(BackupSchedule.hourly.nextRun(after: Self.date("2026-11-08T10:17:00-05:00"), calendar: Self.newYork)
            == Self.date("2026-11-08T11:00:00-05:00"))
    }

    @Test func weeklyNextRun() {
        // 2026-11-08 is a Sunday; weekday 2 is Monday.
        let schedule = BackupSchedule.weekly(weekday: 2, hour: 9, minute: 30)
        #expect(schedule.nextRun(after: Self.date("2026-11-08T12:00:00-05:00"), calendar: Self.newYork)
            == Self.date("2026-11-09T09:30:00-05:00"))
    }

    @Test func manualHasNoNextRun() {
        #expect(BackupSchedule.manual.nextRun(after: Self.created, calendar: Self.newYork) == nil)
    }

    @Test func springForwardDaily() {
        // 2:30 AM doesn't exist on 2027-03-14 in New York; the run moves to 3:00 AM EDT.
        let next = BackupSchedule.daily(hour: 2, minute: 30)
            .nextRun(after: Self.date("2027-03-14T00:00:00-05:00"), calendar: Self.newYork)
        #expect(next == Self.date("2027-03-14T03:00:00-04:00"))
    }

    @Test func fallBackDailyRunsOnce() {
        let schedule = BackupSchedule.daily(hour: 1, minute: 30)
        let first = schedule.nextRun(after: Self.date("2026-11-01T00:00:00-04:00"), calendar: Self.newYork)
        #expect(first == Self.date("2026-11-01T01:30:00-04:00"))
        let second = schedule.nextRun(after: first!, calendar: Self.newYork)
        #expect(second == Self.date("2026-11-02T01:30:00-05:00"))
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        var job = Self.job()
        job.schedule = .weekly(weekday: 3, hour: 4, minute: 5)
        job.versions.location = .custom(.cloud(remote: "b2", path: "old"))
        job.approvedFingerprint = job.fingerprint
        job.approvedAt = Self.created
        let outcomes: [BackupRunSummary.Outcome] = [.completed, .failed("boom"), .cancelled, .limitHit]
        for outcome in outcomes {
            job.lastRun = BackupRunSummary(
                startedAt: Self.created, finishedAt: Self.created.addingTimeInterval(60),
                trigger: .scheduled, outcome: outcome,
                copied: 12, replaced: 2, removed: 1, errors: 0, bytes: 48_213_004
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(BackupJob.self, from: encoder.encode(job))
            #expect(decoded == job)
        }
    }

    @Test func scheduleJSONMatchesSpec() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let daily = String(decoding: try encoder.encode(BackupSchedule.daily(hour: 2, minute: 0)), as: UTF8.self)
        #expect(daily == #"{"hour":2,"kind":"daily","minute":0}"#)
        let manual = String(decoding: try encoder.encode(BackupSchedule.manual), as: UTF8.self)
        #expect(manual == #"{"kind":"manual"}"#)
    }
}
