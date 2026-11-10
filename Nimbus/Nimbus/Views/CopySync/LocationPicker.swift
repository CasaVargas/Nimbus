import AppKit
import SwiftUI
import RcloneKit

/// Picks a folder in a cloud (cloud menu + path field + folder browser) or,
/// through "This Mac…", a folder on this Mac via the system open panel.
/// Shared by Copy Between Clouds and the backup editor.
struct LocationPicker: View {
    let label: LocalizedStringKey
    let remoteNames: [String]
    let client: RcloneClient
    @Binding var endpoint: TransferEndpoint?
    /// `.row` is a labelled form row (the backup editor). `.stacked` puts
    /// the menu above the path, for a narrow column (Copy Between Clouds).
    var layout: Layout = .row

    enum Layout { case row, stacked }

    @State private var isBrowsing = false

    private static let thisMacTag = "\u{0}this-mac"
    private static let rowPathWidth: CGFloat = 270

    var body: some View {
        Group {
            switch layout {
            case .row:
                FormRow(label: label, help: nil) {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        menu.frame(width: 140)
                        // One width for every kind of place, so the menus of
                        // stacked rows line up whatever each row holds.
                        HStack(spacing: DesignSystem.Spacing.s) {
                            pathControls(fieldWidth: .infinity)
                        }
                        .frame(width: Self.rowPathWidth, alignment: .leading)
                    }
                }
            case .stacked:
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                    menu.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: DesignSystem.Spacing.s) {
                        pathControls(fieldWidth: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: $isBrowsing) {
            if case .cloud(let remote, _) = endpoint {
                FolderBrowserSheet(remote: remote, client: client) { chosen in
                    endpoint = .cloud(remote: remote, path: chosen)
                }
            }
        }
    }

    private var menu: some View {
        Picker("", selection: menuSelection) {
            Text("Choose…").tag("")
            Text("This Mac…").tag(Self.thisMacTag)
            if !remoteNames.isEmpty { Divider() }
            ForEach(remoteNames, id: \.self) { name in
                Text(verbatim: name).tag(name)
            }
        }
        .labelsHidden()
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func pathControls(fieldWidth: CGFloat) -> some View {
        switch endpoint {
        case .local(let path):
            localFolder(path)
        case .cloud(let remote, _):
            TextField("/", text: cloudPath)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: fieldWidth)
            Button {
                isBrowsing = true
            } label: {
                Image(systemName: "folder")
            }
            .help("Browse folders")
            .accessibilityLabel("Browse folders in \(remote)")
        case nil:
            // No dead text field before a place is chosen.
            Text("No folder chosen yet")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .frame(maxWidth: fieldWidth, minHeight: 22, alignment: .leading)
        }
    }

    private func localFolder(_ path: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(verbatim: FileManager.default.displayName(atPath: path))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)
            Button("Change…") { chooseMacFolder() }
        }
    }

    /// The menu's value: "" (none), the This Mac tag, or a cloud name.
    private var menuSelection: Binding<String> {
        Binding(
            get: {
                switch endpoint {
                case .local: Self.thisMacTag
                case .cloud(let remote, _): remote
                case nil: ""
                }
            },
            set: { newValue in
                switch newValue {
                case "": endpoint = nil
                case Self.thisMacTag: chooseMacFolder()
                default:
                    if endpoint?.cloudName != newValue {
                        endpoint = .cloud(remote: newValue, path: "")
                    }
                }
            }
        )
    }

    private var cloudPath: Binding<String> {
        Binding(
            get: {
                if case .cloud(_, let path) = endpoint { return path }
                return ""
            },
            set: { newPath in
                if case .cloud(let remote, _) = endpoint {
                    endpoint = .cloud(remote: remote, path: newPath)
                }
            }
        )
    }

    /// Cancelling the panel keeps the previous choice.
    private func chooseMacFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        if case .local(let path) = endpoint {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Directory URLs end in "/"; keep the plain POSIX path rclone expects.
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        endpoint = .local(path: path)
    }
}

#Preview {
    VStack {
        LocationPicker(
            label: "Source",
            remoteNames: ["gdrive", "b2"],
            client: RcloneClient(),
            endpoint: .constant(.local(path: NSHomeDirectory() + "/Documents"))
        )
        LocationPicker(
            label: "Destination",
            remoteNames: ["gdrive", "b2"],
            client: RcloneClient(),
            endpoint: .constant(.cloud(remote: "b2", path: "mac-backup/Documents"))
        )
        LocationPicker(
            label: "Empty",
            remoteNames: ["gdrive", "b2"],
            client: RcloneClient(),
            endpoint: .constant(nil)
        )
    }
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 600)
}
