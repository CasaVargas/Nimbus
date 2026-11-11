import SwiftUI
import RcloneKit
import UniformTypeIdentifiers

/// Trailing inspector for the Files tab. Reference: Finder's Get Info and
/// the Preview pane. Reads selection straight from the browser model, so it
/// needs no state of its own.
struct FileInspector: View {
    let remote: String
    let model: BrowserViewModel
    var onQuickLook: ([FileItem]) -> Void
    var onCopy: (FileItem) -> Void

    @Environment(CloudMonitor.self) private var monitor

    static let width: CGFloat = 240

    private var selected: [FileItem] {
        model.sortedFiles.filter { model.selection.ids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            let items = selected
            if items.count == 1, let file = items.first {
                single(file)
            } else if items.count > 1 {
                multiple(items)
            } else {
                folderSummary
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.l)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Color.semantic.surfaceSubtle.opacity(0.45))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }

    // MARK: - States

    @ViewBuilder
    private func single(_ file: FileItem) -> some View {
        preview(FileIcon.image(for: file))
        Text(verbatim: file.name)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            .lineLimit(2)
            .truncationMode(.middle)
        if !file.isDir {
            CloudStatusColumn(file: file, remote: remote, style: .pill)
        }
        KeepOnThisMacRow(remote: remote, file: file)
        ShareLinkRow(remote: remote, file: file)
        if VersionSupport.showsHistory(for: file, backendType: backendType) {
            FileVersionsRow(remote: remote, file: file)
        }
        keyValues([
            ("Kind", Self.kind(of: file)),
            ("Size", file.isDir ? "--" : FileRowView.formatSize(file.size)),
            ("Modified", file.modTime.map { Self.dateFormatter.string(from: $0) } ?? "--"),
            ("Location", location(of: file)),
        ])
        VStack(spacing: DesignSystem.Spacing.s) {
            if !file.isDir {
                Button("Quick Look") { onQuickLook([file]) }
                    .frame(maxWidth: .infinity)
            }
            Button("Copy to…") { onCopy(file) }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    private func multiple(_ items: [FileItem]) -> some View {
        preview(FileIcon.image(for: items[0]))
        Text("\(items.count) items selected")
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
        let total = items.filter { !$0.isDir }.map(\.size).reduce(0, +)
        keyValues([
            ("Files", "\(items.filter { !$0.isDir }.count)"),
            ("Folders", "\(items.filter(\.isDir).count)"),
            ("Total size", FileRowView.formatSize(total)),
        ])
        Button("Quick Look") { onQuickLook(items.filter { !$0.isDir }) }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(items.allSatisfy(\.isDir))
    }

    @ViewBuilder
    private var folderSummary: some View {
        preview(FileIcon.folder)
        Text(verbatim: currentFolderName)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            .lineLimit(2)
        let files = model.sortedFiles
        let total = files.filter { !$0.isDir }.map(\.size).reduce(0, +)
        keyValues([
            ("Items", "\(files.count)"),
            ("Size of files", FileRowView.formatSize(total)),
            ("Location", model.path.isEmpty ? remote : "\(remote) › \(model.path)"),
        ])
        Text("Select a file to see its details.")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
    }

    // MARK: - Pieces

    private func preview(_ image: NSImage) -> some View {
        RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
            .fill(DesignSystem.Color.semantic.surfaceSubtle)
            .frame(height: 110)
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
            }
            .accessibilityHidden(true)
    }

    private func keyValues(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.0)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Spacer(minLength: DesignSystem.Spacing.s)
                    Text(verbatim: row.1)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .font(DesignSystem.Typography.caption)
            }
        }
    }

    /// The cloud's own backend type (not alias-resolved: see `VersionSupport`).
    private var backendType: String? {
        monitor.remotes.first { $0.name == remote }?.type
    }

    private var currentFolderName: String {
        let leaf = (model.path as NSString).lastPathComponent
        return leaf.isEmpty ? remote : leaf
    }

    private func location(of file: FileItem) -> String {
        let parent = (file.path as NSString).deletingLastPathComponent
        return parent.isEmpty ? remote : "\(remote) › \(parent)"
    }

    static func kind(of file: FileItem) -> String {
        if file.isDir { return "Folder" }
        let ext = (file.name as NSString).pathExtension
        if ext.isEmpty { return "Document" }
        return UTType(filenameExtension: ext)?.localizedDescription ?? "\(ext.uppercased()) file"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// The inspector's **Keep on this Mac** switch: the in-app twin of Finder's
/// Keep Downloaded / Allow Removing Download actions. Disabled, with the
/// reason, when the cloud isn't shown in Finder (there's no local copy to
/// keep) or when a folder above is already kept.
struct KeepOnThisMacRow: View {
    let remote: String
    let file: FileItem

    @Environment(FileProviderBridge.self) private var bridge
    @Environment(AppSettings.self) private var settings
    @State private var isPinned = false
    @State private var isKeptByFolder = false
    @State private var error: String?

    private var identifier: String { "\(remote):\(file.path)" }
    private var inFinder: Bool { FinderIntegration.isShown(remote: remote, settings: settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Toggle(isOn: Binding(get: { isPinned || isKeptByFolder }, set: { set($0) })) {
                Text("Keep on this Mac")
                    .font(DesignSystem.Typography.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!inFinder || isKeptByFolder || PinStore.shared == nil)
            Text(verbatim: caption)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(error == nil ? DesignSystem.Color.semantic.textSecondary
                                              : DesignSystem.Color.semantic.statusError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .task(id: identifier) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .nimbusPinsChanged)) { _ in reload() }
    }

    private var caption: String {
        if let error { return error }
        if !inFinder { return "Show this cloud in Finder to keep files on this Mac." }
        if isKeptByFolder { return "Kept because a folder it's in is kept on this Mac." }
        if isPinned {
            return file.isDir ? "Everything in this folder stays downloaded and up to date."
                              : "Stays downloaded and up to date."
        }
        return "Downloads when you open it. macOS can remove the download to free space."
    }

    private func reload() {
        let pins = PinStore.shared?.pins(domain: remote) ?? []
        isPinned = pins.contains(identifier)
        isKeptByFolder = PinPolicy.keptByAncestor(
            identifier, pins: pins, rootKey: PinPolicy.rootKey)
    }

    private func set(_ keep: Bool) {
        error = nil
        isPinned = keep
        Task {
            do {
                try await bridge.setKeepDownloaded(keep, remote: remote, path: file.path)
            } catch {
                self.error = "Couldn't change this: \(error.localizedDescription)"
                reload()
            }
        }
    }
}

/// The inspector's **Share** row: copy a public link to the selected item,
/// choose when it expires and take it back, each only where the service
/// supports it (`ShareLinkSupport`).
struct ShareLinkRow: View {
    let remote: String
    let file: FileItem
    /// Previews set these; the app reads them from the cloud itself.
    var canShareOverride: Bool?
    var supportOverride: ShareLinkSupport?

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(CloudMonitor.self) private var monitor
    @State private var chosenExpiry: ShareLinkSupport.Expiry?
    @State private var state: ShareState = .idle

    enum ShareState: Equatable {
        case idle, working, copied(ShareLinkSupport.Expiry?), stopped, failed(String)
    }

    private var canShare: Bool {
        canShareOverride ?? CloudCapabilities.shared?.canShare(cloud: remote) ?? false
    }
    private var support: ShareLinkSupport {
        if let supportOverride { return supportOverride }
        let cloud = monitor.remotes.first { $0.name == remote }
        return .forBackend(cloud.map { CloudNaming.resolvedType(of: $0, in: monitor.remotes) } ?? "")
    }
    /// Nil when the service takes no expiry.
    private var expiry: ShareLinkSupport.Expiry? {
        guard !support.expiryChoices.isEmpty else { return nil }
        if let chosenExpiry, support.expiryChoices.contains(chosenExpiry) { return chosenExpiry }
        return support.defaultExpiry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Button {
                copy()
            } label: {
                Label("Copy Share Link", systemImage: "link")
            }
            .controlSize(.small)
            .disabled(!canShare || state == .working)
            if canShare, let expiry {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Expires")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Picker("Expires", selection: Binding(get: { expiry }, set: { chosenExpiry = $0 })) {
                        ForEach(support.expiryChoices) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    .accessibilityLabel("Link expires after")
                }
            }
            Text(verbatim: caption)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(captionColor)
                .fixedSize(horizontal: false, vertical: true)
            if canShare && support.canStopSharing {
                Button("Stop Sharing") { stopSharing() }
                    .controlSize(.small)
                    .disabled(state == .working)
                    .help("Turn off this item's share link")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .onChange(of: file.path) { state = .idle }
        .onChange(of: remote) {
            state = .idle
            chosenExpiry = nil
        }
    }

    private var caption: String {
        switch state {
        case .copied(let expiry): return ShareLinkSupport.copiedCaption(expiry: expiry)
        case .stopped: return "Sharing stopped. The old link no longer works."
        case .failed(let message): return message
        case .working: return "Working…"
        case .idle:
            return canShare ? "Anyone with the link can open it." : "This service doesn't make share links."
        }
    }

    private var captionColor: Color {
        switch state {
        case .copied, .stopped: DesignSystem.Color.semantic.statusOK
        case .failed: DesignSystem.Color.semantic.statusError
        default: DesignSystem.Color.semantic.textSecondary
        }
    }

    private func copy() {
        let expiry = expiry
        state = .working
        Task {
            do {
                guard let url = try await daemon.client.publicLink(
                    fs: "\(remote):", remote: file.path, expire: expiry?.duration) else {
                    state = .failed("The service didn't return a link.")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                state = .copied(expiry)
            } catch {
                state = .failed("Couldn't make a link: \(Self.firstLine(of: error))")
            }
        }
    }

    private func stopSharing() {
        state = .working
        Task {
            do {
                try await daemon.client.publicLink(fs: "\(remote):", remote: file.path, unlink: true)
                state = .stopped
            } catch {
                state = .failed("Couldn't stop sharing: \(Self.firstLine(of: error))")
            }
        }
    }

    private static func firstLine(of error: Error) -> String {
        let text = error.localizedDescription
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

#if DEBUG
#Preview("Keep on this Mac") {
    let file = FileItem(path: "Photos/Half Dome.heic", name: "Half Dome.heic", size: 8_400_000,
                        mimeType: "image/heic", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Personal:Photos/Half Dome.heic")
    VStack(spacing: 12) {
        KeepOnThisMacRow(remote: "Personal", file: file)
        ShareLinkRow(remote: "Personal", file: file)
    }
    .padding()
    .frame(width: FileInspector.width)
    .environment(FileProviderBridge())
    .environment(AppSettings(defaults: UserDefaults(suiteName: "KeepPreview")!))
    .environment(RcloneDaemon())
    .environment(CloudMonitor(loadRemotes: { [] }, status: RemoteStatusService(client: RcloneDaemon().client)))
}
#Preview("Share row states") {
    let file = FileItem(path: "Photos/Half Dome.heic", name: "Half Dome.heic", size: 8_400_000,
                        mimeType: "image/heic", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Personal:Photos/Half Dome.heic")
    VStack(spacing: 12) {
        ShareLinkRow(remote: "Personal", file: file, canShareOverride: false)
        ShareLinkRow(remote: "Personal", file: file, canShareOverride: true, supportOverride: .forBackend("drive"))
        ShareLinkRow(remote: "Personal", file: file, canShareOverride: true, supportOverride: .forBackend("s3"))
        ShareLinkRow(remote: "Personal", file: file, canShareOverride: true, supportOverride: .forBackend("kdrive"))
    }
    .padding()
    .frame(width: FileInspector.width)
    .environment(RcloneDaemon())
    .environment(CloudMonitor(loadRemotes: { [] }, status: RemoteStatusService(client: RcloneDaemon().client)))
}
#endif
