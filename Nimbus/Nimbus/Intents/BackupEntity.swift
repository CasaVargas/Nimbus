import AppIntents
import Foundation

/// A saved backup, as Shortcuts lists it.
struct BackupEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Backup"
    static let defaultQuery = BackupEntityQuery()

    let id: UUID
    let name: String
    /// "Documents → b2/Docs"
    let route: String

    init(job: BackupJob) {
        id = job.id
        name = job.name
        route = "\(job.source.displayName) → \(job.destination.displayName)"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(route)")
    }
}

struct BackupEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [BackupEntity.ID]) async throws -> [BackupEntity] {
        Self.entities(for: identifiers, in: try await jobs())
    }

    @MainActor
    func suggestedEntities() async throws -> [BackupEntity] {
        Self.suggested(in: try await jobs())
    }

    @MainActor
    func entities(matching string: String) async throws -> [BackupEntity] {
        Self.entities(matching: string, in: try await jobs())
    }

    @MainActor
    private func jobs() async throws -> [BackupJob] {
        let services = try IntentServices.require()
        try await services.waitForBackups()
        return services.backupStore.jobs
    }

    // MARK: - Pure, for tests

    static func entities(for identifiers: [UUID], in jobs: [BackupJob]) -> [BackupEntity] {
        identifiers.compactMap { id in jobs.first { $0.id == id }.map(BackupEntity.init(job:)) }
    }

    /// Every backup, by name.
    static func suggested(in jobs: [BackupJob]) -> [BackupEntity] {
        jobs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(BackupEntity.init(job:))
    }

    static func entities(matching string: String, in jobs: [BackupJob]) -> [BackupEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return suggested(in: jobs) }
        return suggested(in: jobs).filter { $0.name.localizedStandardContains(query) }
    }
}
