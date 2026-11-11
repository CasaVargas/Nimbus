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

    @Environment(\.stratosphere) private var palette

    private typealias S = DesignSystem.Stratosphere

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                pageHeader
                wells
                if operation == .sync {
                    DestructiveCallout(
                        message: "Sync will make the destination identical to the source. Files in the destination not in the source will be deleted."
                    )
                }
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
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.l)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
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
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(operation == .copy ? "Copy between clouds" : "Keep two places in sync")
                    .font(S.Typography.pageTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(operation == .copy
                     ? "Existing destination files are preserved unless they share a name."
                     : "The destination becomes an exact mirror of the source.")
                    .font(S.Typography.lead)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GlassSegmented(
                options: [.init(value: TransferOperation.copy, title: "Copy"),
                          .init(value: TransferOperation.sync, title: "Sync")],
                selection: $operation
            )
            .accessibilityLabel("Mode")
        }
    }

    /// From and To, side by side, each washed in its cloud's colour.
    private var wells: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
            EndpointWell(title: "From", label: "Source", remoteNames: viewModel?.remoteNames ?? [],
                         client: daemon.client, endpoint: $source)
            WellConnector(systemImage: "arrow.right")
            EndpointWell(title: "To", label: "Destination", remoteNames: viewModel?.remoteNames ?? [],
                         client: daemon.client, endpoint: $destination)
        }
    }

    private var runRow: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Button("Save as Backup…") {
                guard let source, let destination else { return }
                var draft = BackupJob.new(source: source, destination: destination, now: Date())
                draft.mode = operation == .sync ? .mirror : .addOnly
                onSaveAsBackup(draft)
            }
            .buttonStyle(.glassCapsule)
            .disabled(!isValid)
            Spacer()
            Button("Preview…") { isPreviewing = true }
                .buttonStyle(.glassCapsule)
                .disabled(!isValid || isRunning)
            Button(isRunning ? "Starting…" : operation == .copy ? "Start Copy" : "Start Sync") {
                Task { await run() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.primaryPill)
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
        .frame(width: 820, height: 540)
        .background { StratosphereBackdrop() }
        .preferredColorScheme(.dark)
}
