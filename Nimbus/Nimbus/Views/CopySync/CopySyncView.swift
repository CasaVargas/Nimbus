import SwiftUI
import RcloneKit

struct CopySyncView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: CopySyncViewModel?

    @State private var operation: TransferOperation = .copy
    @State private var srcRemote = ""
    @State private var srcPath = ""
    @State private var dstRemote = ""
    @State private var dstPath = ""
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
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
        .navigationTitle("Copy / Sync")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = CopySyncViewModel(client: daemon.client)
            }
            await viewModel?.loadRemotes()
        }
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
            PathPicker(
                label: "Source",
                remoteNames: viewModel?.remoteNames ?? [],
                client: daemon.client,
                selectedRemote: $srcRemote,
                path: $srcPath
            )
            PathPicker(
                label: "Destination",
                remoteNames: viewModel?.remoteNames ?? [],
                client: daemon.client,
                selectedRemote: $dstRemote,
                path: $dstPath
            )
        }
    }

    private var runRow: some View {
        HStack {
            Spacer()
            Button(isRunning ? "Running…" : "Run") {
                Task { await run() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || isRunning)
        }
    }

    private var isValid: Bool {
        !srcRemote.isEmpty && !dstRemote.isEmpty
    }

    private func run() async {
        guard let viewModel else { return }
        isRunning = true
        defer { isRunning = false }

        let srcFs = srcPath.isEmpty ? "\(srcRemote):" : "\(srcRemote):\(srcPath)"
        let dstFs = dstPath.isEmpty ? "\(dstRemote):" : "\(dstRemote):\(dstPath)"

        await viewModel.startOperation(
            operation: operation,
            srcFs: srcFs,
            dstFs: dstFs,
            store: store
        )
    }
}

/// File-private destructive-action callout. Used only by CopySyncView to warn
/// users that `Sync` deletes destination-only files. Intentionally not extracted
/// to `Components/` — no other screen currently needs this affordance.
private struct DestructiveCallout: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.10))
        )
    }
}

#Preview {
    CopySyncView()
        .environment(RcloneDaemon())
        .environment(TransferStore())
        .frame(width: 720, height: 540)
}
