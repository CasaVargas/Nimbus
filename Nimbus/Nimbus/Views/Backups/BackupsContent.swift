import SwiftUI

/// The Backups screen without services: rows, banners and empty state from
/// plain values, so RenderPreview can show every state without a daemon.
struct BackupsContent: View {
    struct Row: Identifiable, Equatable {
        let job: BackupJob
        let status: BackupStatus
        let scheduleLine: String
        /// rclone backend type of the destination cloud; nil for this Mac.
        let destinationType: String?
        let isRunning: Bool
        var isQueued = false
        var id: UUID { job.id }
    }

    struct Actions {
        var newBackup: () -> Void = {}
        var edit: (UUID) -> Void = { _ in }
        var preview: (UUID) -> Void = { _ in }
        var backUpNow: (UUID) -> Void = { _ in }
        var stop: (UUID) -> Void = { _ in }
        var showHistory: (UUID) -> Void = { _ in }
        var copyCommand: (UUID) -> Void = { _ in }
        var duplicate: (UUID) -> Void = { _ in }
        var delete: (UUID) -> Void = { _ in }
        var showFileInFinder: () -> Void = {}
    }

    let rows: [Row]
    let loadState: BackupStore.LoadState
    let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            banner
            if rows.isEmpty {
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "Back up a folder automatically",
                    message: "Copy a folder on this Mac or in one cloud to another cloud on a schedule. You see what will change before anything runs.",
                    action: isWritable ? .init(label: "New Backup…", perform: actions.newBackup) : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rows) { row in
                        BackupRow(row: row, actions: actions, isWritable: isWritable)
                            .contextMenu { menu(for: row) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var isWritable: Bool {
        switch loadState {
        case .loaded, .corrupt: true
        case .notLoaded, .readOnly: false
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch loadState {
        case .corrupt:
            bannerView(
                text: "Nimbus couldn't read your saved backups, so it set the file aside and started a new list.",
                tint: DesignSystem.Color.semantic.statusWarning
            )
        case .readOnly:
            bannerView(
                text: "These backups were saved by a newer version of Nimbus. Update Nimbus to change them.",
                tint: DesignSystem.Color.semantic.statusWarning
            )
        case .loaded, .notLoaded:
            EmptyView()
        }
    }

    private func bannerView(text: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Show in Finder", action: actions.showFileInFinder)
                .controlSize(.small)
        }
        .padding(DesignSystem.Spacing.m)
        .background(tint.opacity(0.10))
    }

    @ViewBuilder
    private func menu(for row: Row) -> some View {
        let id = row.job.id
        Button("Edit…") { actions.edit(id) }
            .disabled(!isWritable || row.isRunning)
        Button("Preview…") { actions.preview(id) }
            .disabled(!isWritable || row.isRunning)
        if row.isRunning {
            Button("Stop") { actions.stop(id) }
        } else if row.isQueued {
            Button("Cancel Backup") { actions.stop(id) }
        } else {
            Button("Back Up Now") { actions.backUpNow(id) }
                .disabled(!isWritable || !row.job.isApproved)
        }
        Divider()
        Button("Show History") { actions.showHistory(id) }
        Button("Copy rclone Command") { actions.copyCommand(id) }
        Button("Duplicate") { actions.duplicate(id) }
            .disabled(!isWritable)
        Divider()
        Button("Delete…", role: .destructive) { actions.delete(id) }
            .disabled(!isWritable || row.isRunning)
    }
}

struct BackupRow: View {
    let row: BackupsContent.Row
    let actions: BackupsContent.Actions
    var isWritable = true

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            leadingIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.job.name)
                    .font(DesignSystem.Typography.headline)
                    .lineLimit(1)
                Text(verbatim: Self.route(row.job))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text(verbatim: row.status.sentence)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(tint)
                        .lineLimit(2)
                    if let progress = row.status.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 120)
                    }
                }
                Text(verbatim: row.scheduleLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            trailingButton
                .disabled(!isWritable && !row.isRunning)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BackupStatus.accessibilityLabel(job: row.job, status: row.status, scheduleLine: row.scheduleLine))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let type = row.destinationType {
            ProviderBadge(provider: type, size: 32)
        } else {
            Image(systemName: "desktopcomputer")
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        let id = row.job.id
        if row.isRunning {
            Button("Stop") { actions.stop(id) }
        } else if row.isQueued {
            Button("Cancel") { actions.stop(id) }
        } else if !row.job.isApproved {
            Button("Preview…") { actions.preview(id) }
        } else {
            Button("Back Up Now") { actions.backUpNow(id) }
        }
    }

    private var tint: Color {
        switch row.status.tint {
        case .info: DesignSystem.Color.semantic.statusInfo
        case .secondary: DesignSystem.Color.semantic.textSecondary
        case .warning: DesignSystem.Color.semantic.statusWarning
        case .error: DesignSystem.Color.semantic.statusError
        case .ok: DesignSystem.Color.semantic.statusOK
        }
    }

    /// "Documents → b2 › mac-backup/Documents".
    static func route(_ job: BackupJob) -> String {
        "\(job.source.displayName) → \(describe(job.destination))"
    }

    static func describe(_ endpoint: TransferEndpoint) -> String {
        switch endpoint {
        case .local(let path):
            return (path as NSString).abbreviatingWithTildeInPath
        case .cloud(let remote, let path):
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.isEmpty ? remote : "\(remote) › \(trimmed)"
        }
    }
}

// MARK: - Fixtures

enum BackupsFixtures {
    static let now = Date(timeIntervalSince1970: 1_794_085_200)

    static func job(_ name: String, source: TransferEndpoint, destination: TransferEndpoint,
                    approved: Bool = true, _ mutate: (inout BackupJob) -> Void = { _ in }) -> BackupJob {
        var job = BackupJob.new(source: source, destination: destination, now: now)
        job.name = name
        mutate(&job)
        if approved { job.approvedFingerprint = job.fingerprint }
        return job
    }

    static func summary(_ outcome: BackupRunSummary.Outcome, copied: Int = 12, hoursAgo: Double = 2) -> BackupRunSummary {
        let end = now.addingTimeInterval(-hoursAgo * 3600)
        return BackupRunSummary(startedAt: end.addingTimeInterval(-90), finishedAt: end, trigger: .manual,
                                outcome: outcome, copied: copied, replaced: 0, removed: 1, errors: 0, bytes: 48_213_004)
    }

    static func row(_ job: BackupJob, destinationType: String? = "b2", running: Transfer? = nil, queued: Bool = false) -> BackupsContent.Row {
        let status = BackupStatus.make(job: job, isRunning: running != nil, isQueued: queued, transfer: running, now: now)
        return BackupsContent.Row(job: job, status: status,
                                  scheduleLine: BackupStatus.scheduleLine(job: job, now: now),
                                  destinationType: destinationType, isRunning: running != nil, isQueued: queued)
    }

    static var everyStatus: [BackupsContent.Row] {
        let docs = TransferEndpoint.local(path: "/Users/jonathan/Documents")
        let running = Transfer(jobID: 1, operation: .sync, srcFs: "a", dstFs: "b", startedAt: now, status: .active,
                               origin: .backup, nimbusUUID: UUID(), progress: 0.45, eta: 180)
        return [
            row(job("Documents to B2", source: docs, destination: .cloud(remote: "b2", path: "mac-backup/Documents")), running: running),
            row(job("Photos to Drive", source: .local(path: "/Users/jonathan/Pictures"), destination: .cloud(remote: "gdrive", path: "Photos")),
                destinationType: "drive", queued: true),
            row(job("Work to Dropbox", source: docs, destination: .cloud(remote: "dropbox", path: "Work"), approved: false),
                destinationType: "dropbox"),
            row(job("Projects", source: .local(path: "/Users/jonathan/Projects"), destination: .cloud(remote: "b2", path: "projects")) {
                $0.lastRun = summary(.failed("The source folder isn't available. Is the drive connected?"), hoursAgo: 9)
            }),
            row(job("Music", source: .cloud(remote: "gdrive", path: "Music"), destination: .local(path: "/Volumes/Backup/Music")) {
                $0.lastRun = summary(.limitHit, hoursAgo: 30)
            }, destinationType: nil),
            row(job("Desktop to B2", source: .local(path: "/Users/jonathan/Desktop"), destination: .cloud(remote: "b2", path: "desktop")) {
                $0.lastRun = summary(.completed)
            }),
            row(job("New backup", source: docs, destination: .cloud(remote: "b2", path: "docs2"))),
        ]
    }
}

#Preview("Every status") {
    BackupsContent(rows: BackupsFixtures.everyStatus, loadState: .loaded, actions: .init())
        .frame(width: 720, height: 640)
}

#Preview("Empty") {
    BackupsContent(rows: [], loadState: .loaded, actions: .init())
        .frame(width: 720, height: 420)
}

#Preview("Newer file, dark") {
    BackupsContent(rows: Array(BackupsFixtures.everyStatus.suffix(2)), loadState: .readOnly(version: 2), actions: .init())
        .frame(width: 720, height: 360)
        .preferredColorScheme(.dark)
}
