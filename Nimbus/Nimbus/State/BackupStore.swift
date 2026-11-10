import Foundation
import Observation
import os

/// The saved backup jobs and their persistence. The only writer of
/// `backups-v1.json`.
@Observable
@MainActor
final class BackupStore {
    enum LoadState: Equatable {
        case notLoaded
        case loaded
        /// The file couldn't be read; it was moved aside (when possible).
        case corrupt(quarantinedAt: URL?)
        /// Written by a newer Nimbus. Shown, never overwritten.
        case readOnly(version: Int)
    }

    private(set) var jobs: [BackupJob] = []
    private(set) var loadState: LoadState = .notLoaded

    /// Called after every change to a job's schedule inputs (edit, delete,
    /// approval, pause, finished run) so the scheduler can re-plan.
    @ObservationIgnored var onJobsChanged: (@MainActor () -> Void)?

    @ObservationIgnored private let file: any BackupsPersisting
    @ObservationIgnored private let writer: BackupsWriter
    @ObservationIgnored private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "backups")

    var fileURL: URL { file.fileURL }

    init(file: any BackupsPersisting = BackupsFile()) {
        self.file = file
        writer = BackupsWriter(file: file)
    }

    func load() async {
        do {
            jobs = try await file.load()
            loadState = .loaded
        } catch BackupsFileError.unsupportedVersion(let version) {
            logger.error("Backups file version \(version) is unsupported; leaving it untouched")
            jobs = []
            loadState = .readOnly(version: version)
        } catch BackupsFileError.corrupt {
            logger.error("Backups file is corrupt; quarantining it")
            jobs = []
            loadState = .corrupt(quarantinedAt: await file.quarantineCorruptFile())
        } catch {
            // An I/O failure (permissions, disk) is not corruption: leave the
            // file alone and stay unwritable so nothing overwrites it.
            logger.error("Unable to read backups file: \(error.localizedDescription)")
            jobs = []
            loadState = .notLoaded
        }
    }

    func job(id: UUID) -> BackupJob? {
        jobs.first { $0.id == id }
    }

    /// Inserts a new job or replaces the one with the same id.
    func upsert(_ job: BackupJob) async {
        guard isWritable else { return }
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        await persist()
        onJobsChanged?()
    }

    func delete(id: UUID) async {
        guard isWritable else { return }
        jobs.removeAll { $0.id == id }
        await persist()
        onJobsChanged?()
    }

    /// Records approval of a preview. Ignored when the job changed since the
    /// preview was taken (the fingerprint no longer matches).
    func approve(id: UUID, fingerprint: String, now: Date = Date()) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].fingerprint == fingerprint else { return }
        jobs[index].approvedFingerprint = fingerprint
        jobs[index].approvedAt = now
        await persist()
        onJobsChanged?()
    }

    func recordRun(id: UUID, summary: BackupRunSummary) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].lastRun = summary
        await persist()
        onJobsChanged?()
    }

    func setPaused(id: UUID, _ paused: Bool) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].isPaused = paused
        await persist()
        onJobsChanged?()
    }

    /// Edits are refused until the file loaded cleanly (or was missing), so a
    /// newer or damaged file is never replaced by a near-empty one.
    var isWritable: Bool {
        switch loadState {
        case .loaded, .corrupt: true
        case .notLoaded, .readOnly: false
        }
    }

    private func persist() async {
        guard isWritable else { return }
        do {
            try await writer.save(jobs)
        } catch {
            logger.error("Unable to save backups: \(error.localizedDescription)")
        }
    }
}
