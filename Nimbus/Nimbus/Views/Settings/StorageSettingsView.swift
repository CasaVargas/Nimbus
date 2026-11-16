import SwiftUI

/// Settings → Storage: how much of this Mac each Finder drive's downloaded
/// files take, and removing those downloads. Files stay in the cloud and in
/// Finder; they download again when opened.
struct StorageSettingsView: View {
    @State private var model: DownloadedStorageModel
    @State private var confirmation: Confirmation?

    private enum Confirmation: Identifiable {
        case drive(String)
        case all
        var id: String {
            switch self {
            case .drive(let remote): "drive:\(remote)"
            case .all: "all"
            }
        }
    }

    init(model: DownloadedStorageModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                FormSection(
                    title: "Downloaded files",
                    footer: "Removing downloads frees space on this Mac. Files stay in your clouds and in Finder, and download again when you open them. Files you keep downloaded aren't removed."
                ) {
                    content
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .accessibilityIdentifier("settings-storage")
        .task { await model.load() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { target in
            Button("Remove Downloads", role: .destructive) {
                Task {
                    switch target {
                    case .drive(let remote): await model.removeDownloads(remote: remote)
                    case .all: await model.removeAllDownloads()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Files stay in your clouds and in Finder, and download again when you open them.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.state != .loaded && model.drives.isEmpty {
            HStack(spacing: DesignSystem.Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Measuring…")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.themeText(.secondary))
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        } else if model.drives.isEmpty {
            Text("No clouds are in Finder.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.themeText(.secondary))
                .padding(.vertical, DesignSystem.Spacing.xs)
        } else {
            FormRow(label: "All drives", help: nil) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    sizeText(model.totalBytes)
                    Button("Remove All Downloads…", role: .destructive) { confirmation = .all }
                        .controlSize(.small)
                        .disabled(model.totalBytes == 0 || model.isRemoving)
                }
            }
            ForEach(model.drives) { drive in
                DriveRow(drive: drive, isRemoving: model.removing.contains(drive.remote)) {
                    confirmation = .drive(drive.remote)
                }
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .drive(let remote): String(localized: "Remove downloaded files from \(remote)?")
        case .all, nil: String(localized: "Remove all downloaded files?")
        }
    }

    private func sizeText(_ bytes: Int64) -> some View {
        Text(verbatim: bytes == 0 ? String(localized: "None") : ByteText.format(bytes))
            .font(DesignSystem.Typography.body)
            .monospacedDigit()
            .foregroundStyle(.themeText(.secondary))
    }
}

private struct DriveRow: View {
    let drive: DownloadedStorageModel.Drive
    let isRemoving: Bool
    let remove: () -> Void

    var body: some View {
        FormRow(label: LocalizedStringKey(stringLiteral: drive.remote), help: help) {
            HStack(spacing: DesignSystem.Spacing.s) {
                if isRemoving {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Removing downloads from \(drive.remote)")
                }
                Text(verbatim: drive.bytes == 0 ? String(localized: "None")
                     : ByteText.format(drive.bytes))
                    .font(DesignSystem.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(.themeText(.secondary))
                Button("Remove Downloads…", action: remove)
                    .controlSize(.small)
                    .disabled(drive.fileCount == 0 || isRemoving)
                    .accessibilityLabel("Remove downloads from \(drive.remote)")
            }
        }
    }

    private var help: LocalizedStringKey? {
        guard drive.fileCount > 0 else { return nil }
        if drive.keptCount > 0 {
            return "^[\(drive.fileCount) file](inflect: true) downloaded. ^[\(drive.keptCount) file](inflect: true) not removed: kept downloaded, open, or not yet uploaded."
        }
        return "^[\(drive.fileCount) file](inflect: true) downloaded"
    }
}

#Preview {
    StorageSettingsView(model: DownloadedStorageModel(source: .init(
        domains: { ["Google Drive", "Dropbox", "S3"] },
        entries: { remote in
            remote == "S3" ? [] : [
                MaterializedEntry(identifier: "\(remote):a.mov", filename: "a.mov", size: 1_400_000_000, isFolder: false),
                MaterializedEntry(identifier: "\(remote):b.pdf", filename: "b.pdf", size: 2_300_000, isFolder: false),
            ]
        },
        pins: { _ in [] },
        evict: { _, _ in 0 }
    )))
    .frame(width: 680, height: 520)
}
