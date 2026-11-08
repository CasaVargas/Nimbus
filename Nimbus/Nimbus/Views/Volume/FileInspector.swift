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

#if DEBUG
#Preview("Keep on this Mac") {
    let file = FileItem(path: "Photos/Half Dome.heic", name: "Half Dome.heic", size: 8_400_000,
                        mimeType: "image/heic", modTime: Date(), isDir: false, fileID: nil,
                        qualifiedRemotePath: "Personal:Photos/Half Dome.heic")
    VStack(spacing: 12) {
        KeepOnThisMacRow(remote: "Personal", file: file)
    }
    .padding()
    .frame(width: FileInspector.width)
    .environment(FileProviderBridge())
    .environment(AppSettings(defaults: UserDefaults(suiteName: "KeepPreview")!))
}
#endif
