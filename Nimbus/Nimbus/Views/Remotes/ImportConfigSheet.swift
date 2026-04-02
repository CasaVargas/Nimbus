import SwiftUI
import AppKit
import RcloneKit

struct ImportConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon

    var onComplete: (() -> Void)?

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
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if parsedRemotes.isEmpty {
                    emptyState
                } else {
                    remoteList
                }
            }
            .navigationTitle("Import rclone Config")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task { await importSelected() }
                    }
                    .disabled(selected.isEmpty || isImporting || parsedRemotes.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 380)
        .task {
            await loadExistingNames()
        }
    }

    // MARK: - Empty state (no file chosen yet)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No file selected")
                .font(.headline)
            Text("Choose an rclone configuration file to import remotes from.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Choose File...") {
                pickFile()
            }
            .buttonStyle(.borderedProminent)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Remote list (after file parsed)

    private var remoteList: some View {
        VStack(spacing: 0) {
            // File path header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(fileURL?.lastPathComponent ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose Different File...") {
                    pickFile()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(parsedRemotes) { remote in
                        RemoteImportRow(
                            remote: remote,
                            isSelected: selected.contains(remote.id),
                            isConflict: isConflict(remote),
                            rename: renameBinding(for: remote),
                            onToggle: { toggle(remote) }
                        )
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }

            if let error {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .padding()
            }

            if isImporting {
                Divider()
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Importing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
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
            self.error = "Could not read file: \(error.localizedDescription)"
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
        error = nil
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
            }
            onComplete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func isConflict(_ remote: ParsedRemote) -> Bool {
        let effectiveName = renames[remote.id].flatMap { $0.isEmpty ? nil : $0 } ?? remote.name
        return existingNames.contains(effectiveName)
    }

    private func toggle(_ remote: ParsedRemote) {
        if selected.contains(remote.id) {
            selected.remove(remote.id)
        } else {
            selected.insert(remote.id)
        }
    }

    private func renameBinding(for remote: ParsedRemote) -> Binding<String> {
        Binding(
            get: { renames[remote.id] ?? "" },
            set: { renames[remote.id] = $0 }
        )
    }
}

// MARK: - RemoteImportRow

private struct RemoteImportRow: View {
    let remote: ParsedRemote
    let isSelected: Bool
    let isConflict: Bool
    @Binding var rename: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(remote.name)
                        .font(.body)
                    Text(remote.type)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)

                    if isConflict {
                        Label("Name conflict", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if isConflict && isSelected {
                    HStack(spacing: 6) {
                        Text("Rename to:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("New name", text: $rename)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(maxWidth: 200)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
