import AppKit
import SwiftUI
import RcloneKit

/// The Backups screen: reads the store and the runner, and hosts the
/// editor, preview and delete flows. Layout lives in `BackupsContent`.
struct BackupsView: View {
    /// A pre-filled new backup from Copy Between Clouds' "Save as Backup…".
    @Binding var pendingDraft: BackupJob?
    /// A backup to scroll to, set by a notification click and consumed here.
    @Binding var focusedJob: UUID?
    /// Opens a cloud's Transfers tab.
    var onShowHistory: (String) -> Void = { _ in }

    @Environment(BackupStore.self) private var store
    @Environment(BackupRunner.self) private var runner
    @Environment(CloudMonitor.self) private var monitor
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let original: BackupJob?
        let draft: BackupJob?
    }

    @State private var editing: EditorRequest?
    @State private var previewing: BackupJob?
    @State private var deleting: BackupJob?
    /// Sheet hand-offs wait for the current sheet to finish dismissing.
    @State private var previewAfterEditor: BackupJob?
    @State private var editAfterPreview: BackupJob?
    @State private var engineAlert = false
    @State private var scrollTarget: UUID?

    var body: some View {
        TimelineView(.everyMinute) { context in
            BackupsContent(
                rows: rows(now: context.date),
                loadState: store.loadState,
                actions: actions,
                openAtLoginNote: showsOpenAtLoginNote ? launchAtLogin.enabledBinding : nil,
                scrollTarget: scrollTarget
            )
        }
        .onChange(of: focusedJob, initial: true) {
            guard let id = focusedJob else { return }
            focusedJob = nil
            scrollTarget = id
        }
        .task { launchAtLogin.refresh() }
        .navigationTitle("Backups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = EditorRequest(original: nil, draft: nil)
                } label: {
                    Label("New Backup…", systemImage: "plus")
                }
                .help("New Backup…")
                .disabled(!store.isWritable)
            }
        }
        .onChange(of: pendingDraft?.id, initial: true) {
            guard let draft = pendingDraft else { return }
            pendingDraft = nil
            editing = EditorRequest(original: nil, draft: draft)
        }
        .sheet(item: $editing, onDismiss: {
            if let job = previewAfterEditor {
                previewAfterEditor = nil
                previewing = job
            }
        }) { request in
            BackupEditorSheet(
                original: request.original,
                draft: request.draft,
                remoteNames: monitor.remotes.map(\.name),
                client: daemon.client
            ) { job, needsPreview in
                Task {
                    await store.upsert(job)
                    if needsPreview { previewAfterEditor = store.job(id: job.id) }
                }
            }
        }
        .sheet(item: $previewing, onDismiss: {
            if let job = editAfterPreview {
                editAfterPreview = nil
                editing = EditorRequest(original: job, draft: nil)
            }
        }) { job in
            BackupPreviewSheet(
                subject: .backup(job),
                client: daemon.client,
                onApprove: { preview, runNow in
                    Task {
                        await store.approve(id: job.id, fingerprint: preview.fingerprint)
                        if runNow { await backUpNow(job.id) }
                    }
                },
                onEdit: { editAfterPreview = store.job(id: job.id) }
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Backup", role: .destructive) {
                if let job = deleting { Task { await store.delete(id: job.id) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Files already backed up stay where they are.")
        }
        .alert("Nimbus's connection engine isn't running", isPresented: $engineAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Backups can run once it has started again. Open Home to restart it.")
        }
    }

    private var showsOpenAtLoginNote: Bool {
        OpenAtLoginNote.isShown(schedules: store.jobs.map(\.schedule), openAtLoginIsOn: launchAtLogin.isEnabled)
    }

    private var deleteTitle: String {
        guard let job = deleting else { return "" }
        return String(localized: "Delete the backup “\(job.name)”?")
    }

    private func rows(now: Date) -> [BackupsContent.Row] {
        store.jobs.map { job in
            let isRunning = runner.runningJobID == job.id
            let transfer = runner.activeTransfer(for: job.id)
            let status = BackupStatus.make(job: job, isRunning: isRunning, isQueued: runner.isQueued(job.id),
                                           transfer: transfer, now: now)
            return BackupsContent.Row(
                job: job,
                status: status,
                scheduleLine: BackupStatus.scheduleLine(job: job, now: now),
                destinationType: destinationType(job.destination),
                isRunning: isRunning,
                isQueued: runner.isQueued(job.id)
            )
        }
    }

    private func destinationType(_ endpoint: TransferEndpoint) -> String? {
        guard let name = endpoint.cloudName else { return nil }
        guard let remote = monitor.remotes.first(where: { $0.name == name }) else { return "" }
        return CloudNaming.resolvedType(of: remote, in: monitor.remotes)
    }

    private var actions: BackupsContent.Actions {
        BackupsContent.Actions(
            newBackup: { editing = EditorRequest(original: nil, draft: nil) },
            edit: { id in
                if let job = store.job(id: id) { editing = EditorRequest(original: job, draft: nil) }
            },
            preview: { id in previewing = store.job(id: id) },
            backUpNow: { id in Task { await backUpNow(id) } },
            stop: { id in Task { await runner.stop(id) } },
            showHistory: { id in
                guard let job = store.job(id: id),
                      let cloud = job.destination.cloudName ?? job.source.cloudName else { return }
                onShowHistory(cloud)
            },
            copyCommand: { id in
                guard let job = store.job(id: id) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(BackupRequest.cliCommand(job: job), forType: .string)
            },
            duplicate: { id in
                guard let job = store.job(id: id) else { return }
                Task { await store.upsert(Self.duplicate(of: job)) }
            },
            delete: { id in deleting = store.job(id: id) },
            showFileInFinder: {
                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL.deletingLastPathComponent()])
            }
        )
    }

    private func backUpNow(_ id: UUID) async {
        guard let job = store.job(id: id) else { return }
        guard job.isApproved else {
            previewing = job
            return
        }
        await runner.enqueue(id, trigger: .manual)
        if runner.lastRefusal == .daemonNotConnected { engineAlert = true }
    }

    /// A copy with a new identity, no approval and no history.
    static func duplicate(of job: BackupJob) -> BackupJob {
        var copy = BackupJob.new(source: job.source, destination: job.destination, now: Date())
        copy.name = String(localized: "\(job.name) copy")
        copy.mode = job.mode
        copy.excludes = job.excludes
        copy.versions = job.versions
        copy.removalLimit = job.removalLimit
        copy.schedule = job.schedule
        return copy
    }
}
