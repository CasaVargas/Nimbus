import SwiftUI
import RcloneKit

/// The inspector's **Version History** row, shown only for files on clouds
/// whose service keeps versions rclone can list (`VersionSupport`).
struct FileVersionsRow: View {
    let remote: String
    let file: FileItem

    @State private var isShowingVersions = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Button {
                isShowingVersions = true
            } label: {
                Label("Version History…", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)
            Text("Earlier copies the service kept of this file.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .sheet(isPresented: $isShowingVersions) {
            FileVersionsSheet(remote: remote, file: file)
        }
    }
}

/// Lists a file's earlier versions, newest first, with Restore and Download.
/// Both run as rclone jobs in the transfer drawer.
struct FileVersionsSheet: View {
    let remote: String
    let file: FileItem
    /// Previews set this; the app lists versions from the cloud.
    var versionsOverride: [FileVersion]?

    @Environment(\.dismiss) private var dismiss
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var transfers
    @State private var phase: Phase
    @State private var restoring: FileVersion?
    @State private var status: Status?

    enum Phase: Equatable {
        case loading, loaded([FileVersion]), failed(String)
    }

    enum Status: Equatable {
        case started(String), failed(String)
    }

    init(remote: String, file: FileItem, versionsOverride: [FileVersion]? = nil) {
        self.remote = remote
        self.file = file
        self.versionsOverride = versionsOverride
        _phase = State(initialValue: versionsOverride.map(Phase.loaded) ?? .loading)
    }

    private var fs: String { "\(remote):" }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Version History")
                    .font(DesignSystem.Typography.headline)
                Text(verbatim: file.name)
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            content
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320)
            HStack {
                if let status {
                    Text(verbatim: statusText(status))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(statusColor(status))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.l)
        .frame(width: 440)
        .task { await load() }
        .confirmationDialog(
            restoring.map { "Restore the version saved \(Self.dateText($0.savedAt))?" } ?? "",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            presenting: restoring
        ) { version in
            Button("Restore") { restore(version) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("“\(file.name)” is replaced with this version. The current file is kept as an earlier version.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Looking for earlier versions…")
                .controlSize(.small)
        case .failed(let message):
            Text(verbatim: message)
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.statusError)
                .multilineTextAlignment(.center)
        case .loaded(let versions) where versions.isEmpty:
            Text("No earlier versions. The service may not keep them for this bucket: turn on versioning there to start keeping them.")
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .multilineTextAlignment(.center)
        case .loaded(let versions):
            List(versions) { version in
                row(version)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
        }
    }

    private func row(_ version: FileVersion) -> some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.dateText(version.savedAt))
                    .font(DesignSystem.Typography.body)
                Text(verbatim: FileRowView.formatSize(version.size))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            Spacer()
            Button("Restore…") { restoring = version }
                .help("Make this version the current file")
            Button("Download…") { download(version) }
                .help("Save a copy of this version on this Mac")
        }
        .controlSize(.small)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Actions

    private func load() async {
        guard versionsOverride == nil else { return }
        do {
            phase = .loaded(try await daemon.client.fileVersions(fs: fs, remote: file.path))
        } catch {
            phase = .failed("Couldn't list versions: \(Self.firstLine(of: error))")
        }
    }

    private func restore(_ version: FileVersion) {
        Task {
            do {
                let job = try await daemon.client.copyVersionAsync(
                    fs: fs, version: version, dstFs: fs, dstRemote: file.path)
                transfers.addTransfer(jobId: job, operation: .copy,
                                      srcFs: "\(fs)\(version.path)", dstFs: "\(fs)\(file.path)")
                status = .started("Restoring. Follow it in Transfers.")
            } catch {
                status = .failed("Couldn't restore: \(Self.firstLine(of: error))")
            }
        }
    }

    private func download(_ version: FileVersion) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Save Here")
        panel.message = String(localized: "Choose a folder for this version of “\(file.name)”.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var folder = url.path(percentEncoded: false)
        while folder.count > 1, folder.hasSuffix("/") { folder.removeLast() }
        let name = VersionSupport.downloadName(for: file.name, savedAt: version.savedAt)
        Task {
            do {
                let job = try await daemon.client.copyVersionAsync(
                    fs: fs, version: version, dstFs: folder, dstRemote: name)
                transfers.addTransfer(jobId: job, operation: .copy,
                                      srcFs: "\(fs)\(version.path)", dstFs: "\(folder)/\(name)")
                status = .started("Downloading “\(name)”. Follow it in Transfers.")
            } catch {
                status = .failed("Couldn't download: \(Self.firstLine(of: error))")
            }
        }
    }

    // MARK: - Text

    private func statusText(_ status: Status) -> String {
        switch status {
        case .started(let text), .failed(let text): text
        }
    }

    private func statusColor(_ status: Status) -> Color {
        switch status {
        case .started: DesignSystem.Color.semantic.statusOK
        case .failed: DesignSystem.Color.semantic.statusError
        }
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func firstLine(of error: Error) -> String {
        let text = error.localizedDescription
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

#if DEBUG
#Preview("Version history") {
    let file = FileItem(path: "bkt/docs/report.txt", name: "report.txt", size: 14,
                        mimeType: "text/plain", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Archive:bkt/docs/report.txt")
    let now = Date()
    FileVersionsSheet(remote: "Archive", file: file, versionsOverride: [
        FileVersion(path: "a", name: "a", savedAt: now.addingTimeInterval(-3_600), size: 8_400),
        FileVersion(path: "b", name: "b", savedAt: now.addingTimeInterval(-86_400 * 2), size: 7_900),
        FileVersion(path: "c", name: "c", savedAt: now.addingTimeInterval(-86_400 * 30), size: 1_200),
    ])
    .environment(RcloneDaemon())
    .environment(TransferStore())
}
#Preview("No versions") {
    let file = FileItem(path: "report.txt", name: "report.txt", size: 14,
                        mimeType: "text/plain", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Archive:report.txt")
    FileVersionsSheet(remote: "Archive", file: file, versionsOverride: [])
        .environment(RcloneDaemon())
        .environment(TransferStore())
}
#Preview("Inspector row") {
    let file = FileItem(path: "report.txt", name: "report.txt", size: 14,
                        mimeType: "text/plain", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Archive:report.txt")
    FileVersionsRow(remote: "Archive", file: file)
        .padding()
        .frame(width: FileInspector.width)
}
#endif
