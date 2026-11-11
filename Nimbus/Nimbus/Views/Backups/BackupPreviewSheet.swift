import SwiftUI
import RcloneKit

/// Shows what a backup (or a one-off copy/sync) would do, from a dry run.
struct BackupPreviewSheet: View {
    enum Subject {
        /// A saved backup: Approve / Approve and Back Up Now.
        case backup(BackupJob)
        /// Copy Between Clouds: Done / Start.
        case transfer(SyncRequest, startLabel: LocalizedStringKey)
    }

    let subject: Subject
    let client: any BackupRcloneClient
    var onApprove: (BackupPreview, Bool) -> Void = { _, _ in }
    var onEdit: () -> Void = {}
    var onStart: () -> Void = {}

    @State private var previewer: BackupPreviewer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BackupPreviewContent(
            state: previewer?.state ?? .checking(listed: 0),
            context: context,
            actions: .init(
                cancel: { Task { await previewer?.cancel(); dismiss() } },
                approve: { preview, runNow in dismiss(); onApprove(preview, runNow) },
                edit: { dismiss(); onEdit() },
                start: { dismiss(); onStart() },
                retry: { Task { await run() } }
            )
        )
        .task {
            if previewer == nil { previewer = BackupPreviewer(client: client) }
            await run()
        }
        .onDisappear { Task { await previewer?.cancel() } }
    }

    private var context: BackupPreviewContent.Context {
        switch subject {
        case .backup(let job):
            BackupPreviewContent.Context(
                isBackup: true,
                isMirror: job.mode == .mirror,
                versionsDescription: job.versionsEndpoint.map { endpoint in
                    job.versions.location == .insideDestination
                        ? BackupJob.versionsFolderName
                        : BackupRow.describe(endpoint)
                },
                destinationDescription: BackupRow.describe(job.destination),
                destinationIsLocal: job.destination.cloudName == nil,
                removalLimit: job.mode == .mirror ? job.removalLimit : nil,
                startLabel: nil
            )
        case .transfer(let request, let startLabel):
            BackupPreviewContent.Context(
                isBackup: false,
                isMirror: request.operation == .sync,
                versionsDescription: nil,
                destinationDescription: request.dstFs,
                destinationIsLocal: request.dstFs.hasPrefix("/"),
                removalLimit: nil,
                startLabel: startLabel
            )
        }
    }

    private func run() async {
        guard let previewer else { return }
        switch subject {
        case .backup(let job):
            await previewer.run(job: job)
        case .transfer(let request, _):
            await previewer.run(request: request, fingerprint: "", removalLimit: nil)
        }
    }
}

/// The preview sheet's layout from plain values (RenderPreview fixtures).
struct BackupPreviewContent: View {
    struct Context {
        let isBackup: Bool
        let isMirror: Bool
        /// Where versions go, for the header's second line; nil when off.
        let versionsDescription: String?
        let destinationDescription: String
        let destinationIsLocal: Bool
        let removalLimit: Int?
        let startLabel: LocalizedStringKey?
    }

    struct Actions {
        var cancel: () -> Void = {}
        var approve: (BackupPreview, Bool) -> Void = { _, _ in }
        var edit: () -> Void = {}
        var start: () -> Void = {}
        var retry: () -> Void = {}
    }

    enum Tab: Hashable { case copy, replace, remove }

    let state: BackupPreviewer.State
    let context: Context
    let actions: Actions

    @State private var tab: Tab = .copy
    @State private var pendingConfirmation: (preview: BackupPreview, runNow: Bool)?

    var body: some View {
        SheetChrome(title: "Preview", subtitle: nil) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
                switch state {
                case .idle, .checking:
                    checking
                case .failed(let message):
                    failed(message)
                case .finished(let preview):
                    result(preview)
                }
            }
        } actions: {
            buttons
        }
        .frame(width: 640, height: 560)
        .onChange(of: state, initial: true) {
            // Open on the first list that has something in it.
            guard case .finished(let preview) = state else { return }
            tab = !preview.willCopy.isEmpty ? .copy : !preview.willReplace.isEmpty ? .replace
                : (context.isMirror && !preview.willRemove.isEmpty) ? .remove : .copy
        }
        .alert(
            confirmationTitle,
            isPresented: Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
            Button("Approve", role: .destructive) {
                if let pending = pendingConfirmation { actions.approve(pending.preview, pending.runNow) }
                pendingConfirmation = nil
            }
        }
    }

    // MARK: - States

    private var checking: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Checking what would change…")
                .font(DesignSystem.Typography.headline)
            if case .checking(let listed) = state, listed > 0 {
                Text("\(listed) items checked")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityElement(children: .combine)
    }

    private func failed(_ message: String) -> some View {
        EmptyState(
            icon: "exclamationmark.triangle",
            title: "Couldn't check this backup",
            messageVerbatim: message,
            action: .init(label: "Try Again", perform: actions.retry)
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private func result(_ preview: BackupPreview) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(verbatim: headline(preview))
                .font(DesignSystem.Typography.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !preview.isEmpty, context.isMirror, let versions = context.versionsDescription {
                Text("Replaced and removed files are kept in \(versions).")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            if preview.approxBytes > 0, !preview.isEmpty {
                Text(verbatim: sizeLine(preview.approxBytes))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)

        if preview.limitHit {
            DestructiveCallout(message: "This would remove more than \(BackupStatus.fileCount(context.removalLimit ?? 0)), so the removal limit would stop it. Check the list, then edit the backup to raise or turn off the limit.")
        }
        if !preview.errors.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Nimbus couldn't read these files. Fix them, then preview again:")
                    .font(DesignSystem.Typography.captionEmphasized)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
                ForEach(preview.errors.prefix(20), id: \.self) { path in
                    Text(verbatim: path)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.statusError)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        if !preview.isEmpty {
            Picker("", selection: $tab) {
                Text("Copy (\(preview.willCopy.count))").tag(Tab.copy)
                Text("Replace (\(preview.willReplace.count))").tag(Tab.replace)
                if context.isMirror {
                    Text("Remove (\(preview.willRemove.count))").tag(Tab.remove)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Changes")
            pathList(paths(for: tab, in: preview))
        }
    }

    private func pathList(_ paths: [String]) -> some View {
        List(paths, id: \.self) { path in
            Text(verbatim: path)
                .font(DesignSystem.Typography.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        // The sheet's own glass surface, not the system's opaque list box.
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .glassContentSurface()
        .frame(minHeight: 220)
        .overlay {
            if paths.isEmpty {
                Text("Nothing")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let preview: BackupPreview? = if case .finished(let preview) = state { preview } else { nil }
        if context.isBackup {
            Button("Cancel", action: actions.cancel)
                .keyboardShortcut(.cancelAction)
            if let preview, preview.limitHit || !preview.errors.isEmpty {
                Button("Edit Backup…", action: actions.edit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
            } else {
                Button("Approve") { approve(preview, runNow: false) }
                    .disabled(!(preview?.canApprove ?? false))
                Button("Approve and Back Up Now") { approve(preview, runNow: true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
                    .disabled(!(preview?.canApprove ?? false))
            }
        } else {
            Button("Done", action: actions.cancel)
                .keyboardShortcut(.cancelAction)
            Button(context.startLabel ?? "Start", action: actions.start)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryPill(.small))
                .disabled(preview == nil)
        }
    }

    // MARK: - Helpers

    private func approve(_ preview: BackupPreview?, runNow: Bool) {
        guard let preview, preview.canApprove else { return }
        if preview.needsRemovalConfirmation {
            pendingConfirmation = (preview, runNow)
        } else {
            actions.approve(preview, runNow)
        }
    }

    private var confirmationTitle: String {
        guard let count = pendingConfirmation?.preview.willRemove.count else { return "" }
        let number = count.formatted()
        if context.versionsDescription != nil {
            return String(localized: "This backup will move \(number) files out of \(context.destinationDescription) into versions.")
        }
        return String(localized: "This backup will permanently delete \(number) files from \(context.destinationDescription).")
    }

    private func paths(for tab: Tab, in preview: BackupPreview) -> [String] {
        switch tab {
        case .copy: preview.willCopy
        case .replace: preview.willReplace
        case .remove: preview.willRemove
        }
    }

    func headline(_ preview: BackupPreview) -> String {
        if preview.isEmpty {
            return String(localized: "Everything is already backed up.")
        }
        let copy = Self.files(preview.willCopy.count)
        let replace = preview.willReplace.count.formatted()
        if context.isMirror {
            let remove = preview.willRemove.count.formatted()
            return String(localized: "\(copy) will be copied, \(replace) replaced and \(remove) removed.")
        }
        return String(localized: "\(copy) will be copied and \(replace) replaced.")
    }

    private static func files(_ count: Int) -> String {
        count == 1 ? String(localized: "1 file") : String(localized: "\(count.formatted()) files")
    }

    private func sizeLine(_ bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return context.destinationIsLocal
            ? String(localized: "About \(size) to copy")
            : String(localized: "About \(size) to upload")
    }
}

// MARK: - Fixtures

private enum PreviewFixtures {
    static var context: BackupPreviewContent.Context { BackupPreviewContent.Context(
        isBackup: true, isMirror: true, versionsDescription: ".nimbus-versions",
        destinationDescription: "b2 › mac-backup/Documents", destinationIsLocal: false,
        removalLimit: 100, startLabel: nil
    ) }

    static func preview(copy: Int = 12, replace: Int = 2, remove: Int = 1, errors: [String] = [], limitHit: Bool = false) -> BackupPreview {
        BackupPreview(
            willCopy: (0..<copy).map { "Taxes/2026/receipt-\($0).pdf" },
            willReplace: (0..<replace).map { "Notes/changed-\($0).md" },
            willRemove: (0..<remove).map { "Old/removed-\($0).txt" },
            errors: errors, approxBytes: 48_213_004, limitHit: limitHit, removalLimit: 100,
            fingerprint: "f", finishedAt: .now
        )
    }
}

#Preview("Checking") {
    BackupPreviewContent(state: .checking(listed: 12_400), context: PreviewFixtures.context, actions: .init())
}

#Preview("Result") {
    BackupPreviewContent(state: .finished(PreviewFixtures.preview()), context: PreviewFixtures.context, actions: .init())
}

#Preview("Nothing to do, dark") {
    BackupPreviewContent(state: .finished(PreviewFixtures.preview(copy: 0, replace: 0, remove: 0)),
                         context: PreviewFixtures.context, actions: .init())
        .preferredColorScheme(.dark)
}

#Preview("Limit hit") {
    BackupPreviewContent(state: .finished(PreviewFixtures.preview(copy: 0, replace: 0, remove: 4_812, limitHit: true)),
                         context: PreviewFixtures.context, actions: .init())
}

#Preview("Errors, dark") {
    BackupPreviewContent(state: .finished(PreviewFixtures.preview(errors: ["Library/locked.db"])),
                         context: PreviewFixtures.context, actions: .init())
        .preferredColorScheme(.dark)
}
