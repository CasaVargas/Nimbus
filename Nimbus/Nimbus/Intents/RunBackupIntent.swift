import AppIntents
import Foundation

/// **Run Backup**: the same as Back Up Now. Queues the run and returns; the
/// backup reports its result the usual way (Backups screen, notification).
struct RunBackupIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Backup"
    static let description = IntentDescription(
        "Starts a saved Nimbus backup now. If another backup is running, it starts after that one.",
        categoryName: "Backups")

    @Parameter(title: "Backup")
    var backup: BackupEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$backup)")
    }

    init() {}

    init(backup: BackupEntity) {
        self.backup = backup
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = try IntentServices.require()
        try await services.waitForBackups()
        try await services.waitForDaemon()
        let runner = services.backupRunner
        await runner.enqueue(backup.id, trigger: .manual)
        if let refusal = runner.lastRefusal { throw ShortcutError.backup(refusal) }
        return .result(dialog: "\(Self.startedMessage(name: backup.name, waiting: runner.isQueued(backup.id)))")
    }

    static func startedMessage(name: String, waiting: Bool) -> String {
        waiting ? "“\(name)” starts after the backup that's running." : "Started “\(name)”."
    }
}
