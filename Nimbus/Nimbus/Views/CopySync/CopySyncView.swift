import SwiftUI
import RcloneKit

struct CopySyncView: View {
    /// Remote to preselect as the source when opened from a volume's Sync… button.
    var initialSource: String? = nil
    var initialSourcePath: String? = nil
    /// "Save as Backup…": a pre-filled new backup for the Backups screen.
    var onSaveAsBackup: (BackupJob) -> Void = { _ in }
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: CopySyncViewModel?

    @State private var operation: TransferOperation = .copy
    @State private var source: TransferEndpoint?
    @State private var destination: TransferEndpoint?
    @State private var isRunning = false
    @State private var isPreviewing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                pageHeader
                operationSection
                if operation == .sync {
                    DestructiveCallout(
                        message: "Sync will make the destination identical to the source. Files in the destination not in the source will be deleted."
                    )
                }
                pathsSection
                if let error = viewModel?.error {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't start",
                        messageVerbatim: error.message,
                        action: .init(label: "Dismiss", perform: { viewModel?.clearError() })
                    )
                    .frame(maxHeight: 160)
                }
                runRow
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 720)
        }
        .navigationTitle("Copy Between Clouds")
        .sheet(isPresented: $isPreviewing) {
            if let source, let destination {
                BackupPreviewSheet(
                    subject: .transfer(
                        SyncRequest(operation: operation == .sync ? .sync : .copy, srcFs: source.fs, dstFs: destination.fs),
                        startLabel: operation == .copy ? "Start Copy" : "Start Sync"
                    ),
                    client: daemon.client,
                    onStart: { Task { await run() } }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let initialSource, source == nil {
                source = .cloud(remote: initialSource, path: initialSourcePath ?? "")
            }
        }
        .onChange(of: initialSource) { _, newValue in
            if let newValue {
                source = .cloud(remote: newValue, path: initialSourcePath ?? "")
            }
        }
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = CopySyncViewModel(client: daemon.client)
            }
            await viewModel?.loadRemotes()
        }
    }

    private var pageHeader: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: operation == .copy ? "doc.on.doc.fill" : "arrow.triangle.2.circlepath")
                .font(DesignSystem.Typography.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(operation == .copy ? "Copy between clouds" : "Keep two locations in sync")
                    .font(DesignSystem.Typography.headline)
                Text(operation == .copy
                     ? "Existing destination files are preserved unless they share a name."
                     : "The destination becomes an exact mirror of the source.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .animation(DesignSystem.Motion.snappy, value: operation)
    }

    private var operationSection: some View {
        FormSection(title: "Operation", footer: nil) {
            FormRow(label: "Mode", help: nil) {
                Picker("", selection: $operation) {
                    Text("Copy").tag(TransferOperation.copy)
                    Text("Sync").tag(TransferOperation.sync)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
            }
        }
    }

    private var pathsSection: some View {
        FormSection(title: "Paths", footer: nil) {
            LocationPicker(
                label: "Source",
                remoteNames: viewModel?.remoteNames ?? [],
                client: daemon.client,
                endpoint: $source
            )
            LocationPicker(
                label: "Destination",
                remoteNames: viewModel?.remoteNames ?? [],
                client: daemon.client,
                endpoint: $destination
            )
        }
    }

    private var runRow: some View {
        HStack {
            Button("Save as Backup…") {
                guard let source, let destination else { return }
                var draft = BackupJob.new(source: source, destination: destination, now: Date())
                draft.mode = operation == .sync ? .mirror : .addOnly
                onSaveAsBackup(draft)
            }
            .disabled(!isValid)
            Spacer()
            Button("Preview…") { isPreviewing = true }
                .disabled(!isValid || isRunning)
            Button(isRunning ? "Starting…" : operation == .copy ? "Start Copy" : "Start Sync") {
                Task { await run() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!isValid || isRunning)
        }
    }

    private var isValid: Bool {
        guard let source, let destination else { return false }
        return source != destination
    }

    private func run() async {
        guard let viewModel, let source, let destination else { return }
        isRunning = true
        defer { isRunning = false }

        await viewModel.startOperation(
            operation: operation,
            source: source,
            destination: destination,
            store: store
        )
    }
}

#Preview {
    CopySyncView()
        .environment(RcloneDaemon())
        .environment(TransferStore())
        .frame(width: 720, height: 540)
}
