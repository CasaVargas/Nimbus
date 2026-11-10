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

    @Test func timeZoneChangeMovesSlotToNewWallClock() {
        // The same daily 2:00 AM job, after the Mac moves from New York to Los Angeles.
        let schedule = BackupSchedule.daily(hour: 2, minute: 0)
        let after = Self.date("2026-11-08T01:00:00-05:00") // 10 PM the night before in LA
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(schedule.nextRun(after: after, calendar: Self.newYork) == Self.date("2026-11-08T02:00:00-05:00"))
        #expect(schedule.nextRun(after: after, calendar: losAngeles) == Self.date("2026-11-08T02:00:00-08:00"))
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

/// JSON as phase 1 wrote it: no `movesToVersions`, no `removalLimit`.
enum Phase1JSON {
    static let summary = """
    {"bytes":10,"copied":3,"errors":0,"finishedAt":"2026-11-06T21:21:30Z","outcome":"completed",
     "removed":1,"replaced":1,"startedAt":"2026-11-06T21:20:00Z","trigger":"manual"}
    """

    static let backupsFile = """
    {"version":1,"jobs":[{
      "createdAt":"2026-11-06T21:20:00Z",
      "destination":{"kind":"cloud","path":"mac","remote":"b2"},
      "excludes":[".DS_Store"],
      "id":"55B48132-F41E-4F2F-B564-1A59315D5FFC",
      "isPaused":false,
      "lastRun":\(summary),
      "mode":"mirror","name":"Documents to b2","removalLimit":100,
      "schedule":{"kind":"manual"},
      "source":{"kind":"local","path":"/Users/j/Documents"},
      "versions":{"enabled":true,"keep":"forever","location":{"kind":"insideDestination"}}
    }]}
    """

    static let history = """
    {"version":2,"records":[{
      "backupID":"55B48132-F41E-4F2F-B564-1A59315D5FFC",
      "completedAt":815692890,"destination":"b",
      "id":"C0238F32-D50A-45A7-A353-F225AB5393F0","jobID":1,"operation":"sync","origin":"backup",
      "outcome":{"completed":{}},"source":"a","startedAt":815692800,
      "summary":{"bytes":10,"copied":3,"errors":0,"finishedAt":815692890,"outcome":"completed",
                 "removed":1,"replaced":1,"startedAt":815692800,"trigger":"manual"},
      "title":"T"
    }]}
    """
}

@Suite("Summaries saved by earlier builds")
struct SummaryCompatibilityTests {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryCompat-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func write(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    @Test func summaryWithoutNewKeysDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(BackupRunSummary.self, from: Data(Phase1JSON.summary.utf8))
        #expect(summary.copied == 3)
        #expect(summary.removalLimit == nil)
        #expect(summary.movesToVersions != true)
    }

    @Test func phase1BackupsFileLoads() async throws {
        let url = tempURL("backups-v1.json")
        try write(Phase1JSON.backupsFile, to: url)
        let jobs = try await BackupsFile(url: url).load()
        #expect(jobs.count == 1)
        #expect(jobs.first?.lastRun?.outcome == .completed)
        #expect(jobs.first?.lastRun?.movesToVersions != true)
    }

    @Test func phase1HistoryRecordWithSummaryLoads() async throws {
        let url = tempURL("transfer-history.json")
        try write(Phase1JSON.history, to: url)
        let records = try await TransferHistoryFile(url: url).load()
        #expect(records.count == 1)
        #expect(records.first?.summary?.copied == 3)
    }
}
