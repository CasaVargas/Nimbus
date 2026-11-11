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
        var showVersions: (UUID) -> Void = { _ in }
        var showHistory: (UUID) -> Void = { _ in }
        var copyCommand: (UUID) -> Void = { _ in }
        var duplicate: (UUID) -> Void = { _ in }
        var delete: (UUID) -> Void = { _ in }
        var showFileInFinder: () -> Void = {}
    }

    let rows: [Row]
    let loadState: BackupStore.LoadState
    let actions: Actions
    /// Non-nil shows the Open at Login note with this toggle.
    var openAtLoginNote: Binding<Bool>? = nil
    /// The Run Backups When Nimbus Is Closed toggle shown in that note.
    var runsWhenClosed: Binding<Bool>? = nil
    /// A backup to scroll to, e.g. from a notification.
    var scrollTarget: UUID? = nil

    @Environment(\.stratosphere) private var palette

    private typealias S = DesignSystem.Stratosphere

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
                ScrollViewReader { proxy in
                ScrollView {
                    GlassGroup {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
                        hero
                        Text("Your backups")
                            .font(S.Typography.sectionTitle)
                            .foregroundStyle(palette.textPrimary.color)
                            .padding(.leading, DesignSystem.Spacing.xs)
                            .padding(.top, DesignSystem.Spacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(rows) { row in
                            BackupRow(row: row, actions: actions, isWritable: isWritable)
                                .id(row.id)
                        }
                        if let openAtLoginNote {
                            OpenAtLoginNoteView(isOn: openAtLoginNote, runsWhenClosed: runsWhenClosed)
                                .padding(.horizontal, DesignSystem.Spacing.l)
                                .padding(.vertical, 14)
                                .glassSurface(radius: S.Radius.card)
                        }
                        Label("Every backup shows a preview before it removes or replaces anything.",
                              systemImage: "checkmark.shield")
                            .font(S.Typography.detail)
                            .foregroundStyle(palette.textTertiary.color)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, DesignSystem.Spacing.s)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.l)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                    }
                }
                .onChange(of: scrollTarget, initial: true) {
                    guard let scrollTarget else { return }
                    withAnimation(DesignSystem.Motion.smooth) { proxy.scrollTo(scrollTarget, anchor: .center) }
                }
                }
            }
        }
    }

    /// How the backups stand as a whole, and the way to add one.
    private var hero: some View {
        let headline = BackupsHeadline(statuses: rows.map(\.status))
        let tone: Color = switch headline.tone {
        case .ok: palette.ok.color
        case .warning: palette.warning.color
        case .neutral: palette.actionTop.color
        }
        let shape = RoundedRectangle(cornerRadius: S.Radius.header, style: .continuous)
        return HStack(spacing: DesignSystem.Spacing.l) {
            Circle()
                .fill(tone)
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: headline.tone == .warning ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .font(DesignSystem.Typography.largeTitle)
                        .foregroundStyle(.black.opacity(0.7))
                }
                .shadow(color: tone.opacity(0.45), radius: 14, y: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: headline.title)
                    .font(S.Typography.pageTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let sentence = headline.sentence {
                    Text(verbatim: sentence)
                        .font(S.Typography.lead)
                        .foregroundStyle(palette.textSecondary.color)
                }
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            if isWritable {
                Button(action: actions.newBackup) { Label("New Backup", systemImage: "plus") }
                    .buttonStyle(.primaryPill)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background {
            shape.fill(LinearGradient(colors: [tone.opacity(0.26), tone.opacity(0.04)],
                                      startPoint: .leading, endPoint: .trailing))
        }
        .glassSurface(radius: S.Radius.header)
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
                tint: palette.warning.color
            )
        case .readOnly:
            bannerView(
                text: "These backups were saved by a newer version of Nimbus. Update Nimbus to change them.",
                tint: palette.warning.color
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
                .font(S.Typography.detail)
                .foregroundStyle(palette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Show in Finder", action: actions.showFileInFinder)
                .buttonStyle(.glassCapsule)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.m)
        .background(tint.opacity(0.18))
    }

}

struct BackupRow: View {
    let row: BackupsContent.Row
    let actions: BackupsContent.Actions
    var isWritable = true

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors

    private typealias S = DesignSystem.Stratosphere

    var body: some View {
        HStack(spacing: 14) {
            leadingIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.job.name)
                    .font(S.Typography.sectionTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                Text(verbatim: Self.route(row.job))
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StatusDot(status: status)
                    Text(verbatim: row.status.sentence)
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textPrimary.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let progress = row.status.progress {
                    UsageBar(fraction: progress, color: barColor)
                        .frame(maxWidth: 260)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BackupStatus.accessibilityLabel(job: row.job, status: row.status, scheduleLine: row.scheduleLine))
            Spacer(minLength: DesignSystem.Spacing.m)
            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.s) {
                Label {
                    Text(verbatim: row.scheduleLine)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(S.Typography.detail)
                .foregroundStyle(palette.textSecondary.color)
                .lineLimit(1)
                .accessibilityHidden(true)
                HStack(spacing: DesignSystem.Spacing.s) {
                    trailingButton
                        .buttonStyle(.glassCapsule)
                        .disabled(!isWritable && !row.isRunning)
                    Menu {
                        menuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(palette.textSecondary.color)
                    .help("More actions")
                    .accessibilityLabel("More actions for \(row.job.name)")
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, 14)
        .glassSurface(radius: S.Radius.card)
        .contextMenu { menuItems }
        // The text reads as one element; the buttons stay their own, so
        // pressing the row does not start a backup.
        .accessibilityElement(children: .contain)
    }

    /// Everything a backup can do. Shown from the row's More button and
    /// on right-click, so Edit is not hidden behind a secondary click.
    @ViewBuilder
    private var menuItems: some View {
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
        Button("Show Versions") { actions.showVersions(id) }
            .disabled(VersionsReveal.target(for: row.job, versionsFolderExists: false) == .unavailable)
        Button("Show History") { actions.showHistory(id) }
        Button("Copy rclone Command") { actions.copyCommand(id) }
        Button("Duplicate") { actions.duplicate(id) }
            .disabled(!isWritable)
        Divider()
        Button("Delete…", role: .destructive) { actions.delete(id) }
            .disabled(!isWritable || row.isRunning)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let type = row.destinationType {
            LogoTile(provider: type)
        } else {
            IconTile(systemImage: "desktopcomputer", color: S.CloudColors.sequence[6], size: 42)
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

    /// Shown beside the sentence, so the colour never carries it alone.
    private var status: StratosphereStatus {
        switch row.status.tint {
        case .ok, .info: .ok
        case .secondary: .muted
        case .warning: .warning
        case .error: .error
        }
    }

    /// The destination cloud's colour while a backup runs.
    private var barColor: S.CloudColor {
        if let cloud = row.job.destination.cloudName, let color = cloudColors[cloud] { return color }
        if let type = row.destinationType { return S.CloudColors.color(forProvider: type) }
        return S.CloudColors.home
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
        .frame(width: 900, height: 860)
        .background { StratosphereBackdrop() }
        .preferredColorScheme(.dark)
}

#Preview("Open at Login footer") {
    BackupsContent(rows: Array(BackupsFixtures.everyStatus.prefix(3)), loadState: .loaded, actions: .init(),
                   openAtLoginNote: .constant(false))
        .frame(width: 900, height: 700)
        .background { StratosphereBackdrop() }
}

#Preview("Open at Login footer, dark") {
    BackupsContent(rows: Array(BackupsFixtures.everyStatus.prefix(3)), loadState: .loaded, actions: .init(),
                   openAtLoginNote: .constant(false))
        .frame(width: 900, height: 700)
        .background { StratosphereBackdrop() }
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    BackupsContent(rows: [], loadState: .loaded, actions: .init())
        .frame(width: 720, height: 420)
        .background { StratosphereBackdrop() }
}

#Preview("Newer file, dark") {
    BackupsContent(rows: Array(BackupsFixtures.everyStatus.suffix(2)), loadState: .readOnly(version: 2), actions: .init())
        .frame(width: 720, height: 460)
        .background { StratosphereBackdrop() }
        .preferredColorScheme(.dark)
}
