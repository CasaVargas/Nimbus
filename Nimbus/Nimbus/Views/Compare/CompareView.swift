import SwiftUI
import RcloneKit

/// Compares two folders (any cloud or this Mac) and lists what's the same,
/// what differs and what's only on one side. Read-only.
struct CompareView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @State private var viewModel: CompareViewModel?

    @State private var a: TransferEndpoint?
    @State private var b: TransferEndpoint?
    @State private var method: CheckRequest.Method = .checksum
    /// The places the shown result is for; results go stale when either changes.
    @State private var compared: (a: TransferEndpoint, b: TransferEndpoint)?
    @State private var compareTask: Task<Void, Never>?

    @Environment(\.stratosphere) private var palette

    private typealias S = DesignSystem.Stratosphere

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                pageHeader
                wells
                runRow
                content
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.l)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Compare Folders")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: a) { clearIfStale() }
        .onChange(of: b) { clearIfStale() }
        .onChange(of: method) { clearIfStale(force: true) }
        .onDisappear {
            compareTask?.cancel()
            Task { await viewModel?.stop() }
        }
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = CompareViewModel(client: daemon.client)
            }
            await viewModel?.loadRemotes()
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compare two folders")
                    .font(S.Typography.pageTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("See what's the same, what's different, and what's only on one side. Nothing is copied or changed.")
                    .font(S.Typography.lead)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GlassSegmented(
                options: [.init(value: CheckRequest.Method.checksum, title: String(localized: "Checksum")),
                          .init(value: CheckRequest.Method.sizeOnly, title: String(localized: "Size Only"))],
                selection: $method
            )
            .accessibilityLabel("Compare by")
            .help(method == .checksum
                  ? "Compares size and content wherever both places share a checksum."
                  : "Compares sizes only. Faster, but misses edits that keep the size.")
        }
    }

    private var wells: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.m) {
            EndpointWell(title: "A", label: "Folder A", remoteNames: viewModel?.remoteNames ?? [],
                         client: daemon.client, endpoint: $a)
            WellConnector(systemImage: "arrow.left.arrow.right")
            EndpointWell(title: "B", label: "Folder B", remoteNames: viewModel?.remoteNames ?? [],
                         client: daemon.client, endpoint: $b)
        }
    }

    private var runRow: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            if case .running(let checked) = viewModel?.state {
                ProgressView()
                    .controlSize(.small)
                Text(checked > 0 ? "Comparing… \(checked) files checked" : "Comparing…")
                    .font(S.Typography.detail)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary.color)
                Spacer()
                Button("Stop") {
                    compareTask?.cancel()
                    Task { await viewModel?.stop() }
                }
                .buttonStyle(.glassCapsule)
                .keyboardShortcut(.cancelAction)
            } else {
                if a != nil, a == b {
                    Text("Choose two different folders.")
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                }
                Spacer()
                Button("Compare") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill)
                    .disabled(!isValid || viewModel == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .finished(let result):
            if let compared {
                CompareResultsView(result: result,
                                   nameA: Self.describe(compared.a),
                                   nameB: Self.describe(compared.b))
            }
        case .failed(let message):
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't compare",
                messageVerbatim: message,
                action: .init(label: "Dismiss", perform: { viewModel?.reset() })
            )
            .frame(maxHeight: 160)
        case .idle, .running, nil:
            EmptyView()
        }
    }

    private var isValid: Bool {
        guard let a, let b else { return false }
        return a != b
    }

    private func start() {
        guard let viewModel, let a, let b, isValid else { return }
        compared = (a, b)
        let method = method
        compareTask = Task { await viewModel.compare(a, b, method: method) }
    }

    /// A result describes the places it was run on; changing either clears it.
    private func clearIfStale(force: Bool = false) {
        guard let viewModel, !viewModel.isRunning, let compared else { return }
        if force || compared.a != a || compared.b != b {
            viewModel.reset()
            self.compared = nil
        }
    }

    static func describe(_ endpoint: TransferEndpoint) -> String {
        switch endpoint {
        case .local(let path): (path as NSString).abbreviatingWithTildeInPath
        case .cloud(let remote, let path):
            path.isEmpty ? "\(remote):" : "\(remote): \(path)"
        }
    }
}

#Preview {
    CompareView()
        .environment(RcloneDaemon())
        .frame(width: 900, height: 620)
        .background { StratosphereBackdrop() }
        .preferredColorScheme(.dark)
}
