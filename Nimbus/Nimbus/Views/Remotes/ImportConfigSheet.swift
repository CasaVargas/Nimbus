import SwiftUI
import AppKit
import RcloneKit

struct ImportConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderBridge.self) private var fileProviderBridge

    var onDismiss: (() -> Void)?

    // File selection & parsing state
    @State private var parsedRemotes: [ParsedRemote] = []
    @State private var fileURL: URL?

    // Per-remote selection and rename state
    @State private var selected: Set<UUID> = []
    @State private var renames: [UUID: String] = [:]

    // Existing remote names for conflict detection
    @State private var existingNames: Set<String> = []

    // Operation state
    @State private var isImporting = false
    @State private var error: NimbusError?
    @State private var finderFailures: [RemoteIntegrationFailure] = []

    var body: some View {
        SheetChrome(
            title: "Import from rclone.conf",
            subtitle: fileURL.map { LocalizedStringKey($0.lastPathComponent) },
            body: {
                if parsedRemotes.isEmpty {
                    EmptyState(
                        icon: "square.and.arrow.down",
                        title: "No File Selected",
                        message: "Choose an rclone.conf file. Nimbus adds each cloud in it.",
                        action: .init(label: "Choose File…", perform: { pickFile() })
                    )
                } else {
                    VStack(spacing: 0) {
                        if !finderFailures.isEmpty {
                            FinderIntegrationWarning(failures: finderFailures) {
                                Task { await retryFinderIntegration() }
                            }
                            .padding(DesignSystem.Spacing.m)
                            Divider()
                        }
                        fileHeader
                        Divider()
                        ImportPreviewList(
                            remotes: parsedRemotes,
                            selected: $selected,
                            renames: $renames,
                            isConflict: isConflict
                        )
                        if isImporting {
                            Divider()
                            HStack(spacing: DesignSystem.Spacing.s) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Importing…")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                            }
                            .padding(DesignSystem.Spacing.m)
                        }
                    }
                }
            },
            actions: {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isImporting ? "Importing…" : "Import") {
                    Task { await importSelected() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryPill(.small))
                .disabled(selected.isEmpty || isImporting || parsedRemotes.isEmpty || !finderFailures.isEmpty)
            }
        )
        .frame(minWidth: 540, minHeight: 420)
        .task {
            await loadExistingNames()
        }
        .alert(
            "Import error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(verbatim: err.message)
        }
    }

    private var fileHeader: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(systemName: "doc.text")
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Text(verbatim: fileURL?.lastPathComponent ?? "")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
            Button("Choose Different File…") { pickFile() }
                .buttonStyle(.plain)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.accent)
        }
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, DesignSystem.Spacing.s)
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Select rclone Config File"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an rclone configuration file (usually rclone.conf)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let remotes = RcloneConfParser.parse(content)
            fileURL = url
            parsedRemotes = remotes
            // Pre-select all non-conflicting remotes
            selected = Set(remotes.filter { !isConflict($0) }.map(\.id))
            error = nil
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private func loadExistingNames() async {
        do {
            let names = try await daemon.client.listRemotes()
            existingNames = Set(names)
        } catch {
            // Non-fatal: conflict detection won't work but import can still proceed
        }
    }

    private func importSelected() async {
        isImporting = true
        defer { isImporting = false }

        let toImport = parsedRemotes.filter { selected.contains($0.id) }
        do {
            for remote in toImport {
                let effectiveName = renames[remote.id].flatMap { $0.isEmpty ? nil : $0 } ?? remote.name
                try await daemon.client.createRemote(
                    name: effectiveName,
                    type: remote.type,
                    parameters: remote.parameters
                )
                let result = await NewRemoteIntegration(domainAdder: fileProviderBridge).integrate(
                    names: [effectiveName],
                    addToFinder: settings.addNewRemotesToFinder,
                    disabledDomainNames: settings.disabledFileProviderDomains
                )
                settings.disabledFileProviderDomains = result.disabledDomainNames
                finderFailures += result.failures
            }
            onDismiss?()
            if finderFailures.isEmpty {
                dismiss()
            }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    // MARK: - Helpers

    private func isConflict(_ remote: ParsedRemote) -> Bool {
        let effectiveName = renames[remote.id].flatMap { $0.isEmpty ? nil : $0 } ?? remote.name
        return existingNames.contains(effectiveName)
    }

    private func retryFinderIntegration() async {
        let failedNames = finderFailures.map(\.remoteName)
        finderFailures = await NewRemoteIntegration(domainAdder: fileProviderBridge)
            .integrate(names: failedNames, addToFinder: true)
        if finderFailures.isEmpty {
            dismiss()
        }
    }
}
