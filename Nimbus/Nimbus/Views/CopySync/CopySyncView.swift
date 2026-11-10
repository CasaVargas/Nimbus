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
    @Environment(\.cloudColors) private var cloudColors
    /// Optional so previews without a live window still render.
    @Environment(CloudMonitor.self) private var monitor: CloudMonitor?

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
            well(title: "From", label: "Source", endpoint: $source)
            Circle()
                .fill(LinearGradient(colors: [palette.actionTop.color, palette.actionBottom.color],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "arrow.right")
                        .font(DesignSystem.Typography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.onAction.color)
                }
                .shadow(color: palette.actionGlow.color, radius: 12, y: 6)
                .accessibilityHidden(true)
            well(title: "To", label: "Destination", endpoint: $destination)
        }
    }

    private func well(title: LocalizedStringKey, label: LocalizedStringKey,
                      endpoint: Binding<TransferEndpoint?>) -> some View {
        let place = Place(endpoint: endpoint.wrappedValue, remotes: monitor?.remotes ?? [])
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            Text(title)
                .font(S.Typography.segment)
                .foregroundStyle(palette.textSecondary.color)
            HStack(spacing: DesignSystem.Spacing.m) {
                if let provider = place.provider {
                    LogoTile(provider: provider)
                } else {
                    IconTile(systemImage: place.symbol, color: S.CloudColors.sequence[6], size: 42)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: place.title)
                        .font(S.Typography.sectionTitle)
                        .foregroundStyle(palette.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: place.detail)
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            LocationPicker(
                label: label,
                remoteNames: viewModel?.remoteNames ?? [],
                client: daemon.client,
                endpoint: endpoint,
                layout: .stacked
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: S.Radius.header, tint: place.cloud.flatMap { cloudColors[$0] })
    }

    /// What a well says about its current choice.
    private struct Place {
        let title: String
        let detail: String
        let provider: String?
        let symbol: String
        let cloud: String?

        init(endpoint: TransferEndpoint?, remotes: [Remote]) {
            switch endpoint {
            case .cloud(let remote, let path):
                title = remote
                let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                detail = trimmed.isEmpty ? "The whole cloud" : trimmed
                provider = remotes.first { $0.name == remote }.map { CloudNaming.resolvedType(of: $0, in: remotes) }
                symbol = "cloud.fill"
                cloud = remote
            case .local(let path):
                title = "This Mac"
                detail = (path as NSString).abbreviatingWithTildeInPath
                provider = nil
                symbol = "desktopcomputer"
                cloud = nil
            case nil:
                title = "Choose a place"
                detail = "A cloud, or a folder on this Mac"
                provider = nil
                symbol = "questionmark"
                cloud = nil
            }
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
