import SwiftUI
import RcloneKit

/// The first step of Add Cloud. The services most people add are tiles with
/// their real logo and a line on how signing in works; servers people run
/// or rent are chips; the long tail of rclone backends stays a dense list
/// (with 70+ entries the text is the scan axis there). Searching replaces
/// everything with filtered rows. One click picks a service.
struct ProviderPicker: View {
    let providers: [Provider]
    let onPick: (Provider) -> Void
    /// Shown as the last "storage you run or rent" chip when set.
    var onImport: (() -> Void)? = nil
    /// "New Encrypted Folder…" chip in the same row, when set (#68).
    var onEncryptedFolder: (() -> Void)? = nil
    @State private var search = ""
    @Environment(\.stratosphere) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            HStack(spacing: DesignSystem.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.textTertiary.color)
                    .accessibilityHidden(true)
                TextField(searchPrompt, text: $search)
                    .textFieldStyle(.plain)
                    .foregroundStyle(palette.textPrimary.color)
            }
            .padding(.horizontal, DesignSystem.Spacing.m)
            .frame(height: 36)
            .background(Capsule().fill(palette.glassBottom.color))
            .overlay(Capsule().strokeBorder(palette.glassBorder.color, lineWidth: 1))

            if search.isEmpty {
                if !popular.isEmpty {
                    sectionTitle("Popular")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                              spacing: 10) {
                        ForEach(popular, id: \.provider.name) { entry in
                            ProviderTile(entry: entry, onPick: { onPick(entry.provider) })
                        }
                    }
                }
                if !servers.isEmpty || onImport != nil || onEncryptedFolder != nil {
                    sectionTitle("Storage you run or rent")
                    FlowRows(spacing: DesignSystem.Spacing.s) {
                        ForEach(servers, id: \.provider.name) { entry in
                            ProviderChip(title: entry.title, prefix: entry.provider.prefix,
                                         onPick: { onPick(entry.provider) })
                        }
                        if let onImport {
                            ProviderChip(title: "Import from rclone.conf…", prefix: nil, onPick: onImport)
                        }
                        if let onEncryptedFolder {
                            ProviderChip(title: "New Encrypted Folder…", prefix: "crypt", onPick: onEncryptedFolder)
                        }
                    }
                }
                if !everythingElse.isEmpty {
                    sectionTitle("All services")
                    rowStack(everythingElse)
                }
            } else if filtered.isEmpty {
                Text("No services match “\(search)”.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(palette.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSystem.Spacing.xl)
            } else {
                rowStack(filtered)
            }
        }
    }

    // MARK: - Data

    private var searchPrompt: String {
        providers.count > 1 ? "Search \(providers.count) services" : "Search services"
    }

    private var popular: [PickerCatalog.Entry] { PickerCatalog.entries(PickerCatalog.popular, in: providers) }
    private var servers: [PickerCatalog.Entry] { PickerCatalog.entries(PickerCatalog.servers, in: providers) }

    private var everythingElse: [Provider] {
        let featured = Set((PickerCatalog.popular + PickerCatalog.servers).map(\.prefix))
        return providers
            .filter { !featured.contains($0.prefix) }
            .sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }
    }

    private var filtered: [Provider] {
        let q = search.lowercased()
        return providers
            .filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
                    || (PickerCatalog.title(forPrefix: $0.prefix)?.lowercased().contains(q) ?? false)
            }
            .sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }
    }

    // MARK: - Layout

    private func sectionTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(DesignSystem.Stratosphere.Typography.label)
            .foregroundStyle(palette.textPrimary.color)
            .padding(.top, DesignSystem.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func rowStack(_ rows: [Provider]) -> some View {
        // Plain VStack — SheetChrome owns scrolling; a nested ScrollView
        // reports unbounded height and balloons the sheet.
        VStack(spacing: 0) {
            ForEach(rows, id: \.name) { provider in
                ProviderRow(provider: provider, onPick: { onPick(provider) })
            }
        }
    }
}

/// The services Add Cloud leads with, in plain names, each with a one-line
/// hint about how signing in works. rclone's own descriptions ("Amazon S3
/// Compliant Storage Providers including AWS, …") stay in the long list.
enum PickerCatalog {
    struct Item { let prefix: String; let title: String; let hint: String? }
    struct Entry { let provider: Provider; let title: String; let hint: String? }

    /// Backends whose `config/create` walk is a browser sign-in.
    static let oauthPrefixes: Set<String> = ["drive", "dropbox", "onedrive", "box", "pcloud"]

    static let popular: [Item] = [
        .init(prefix: "drive", title: "Google Drive", hint: "Sign in with Google"),
        .init(prefix: "onedrive", title: "OneDrive", hint: "Personal or work account"),
        .init(prefix: "dropbox", title: "Dropbox", hint: "Sign in with Dropbox"),
        .init(prefix: "iclouddrive", title: "iCloud Drive", hint: "Uses your Apple Account"),
        .init(prefix: "box", title: "Box", hint: "Sign in with Box"),
        .init(prefix: "pcloud", title: "pCloud", hint: "Sign in with pCloud"),
        .init(prefix: "protondrive", title: "Proton Drive", hint: "End-to-end encrypted"),
        .init(prefix: "mega", title: "MEGA", hint: "Email and password"),
    ]

    static let servers: [Item] = [
        .init(prefix: "s3", title: "Amazon S3 and compatible", hint: nil),
        .init(prefix: "b2", title: "Backblaze B2", hint: nil),
        .init(prefix: "sftp", title: "NAS or server (SFTP)", hint: nil),
        .init(prefix: "webdav", title: "WebDAV", hint: nil),
    ]

    static func entries(_ items: [Item], in providers: [Provider]) -> [Entry] {
        items.compactMap { item in
            providers.first { $0.prefix == item.prefix }.map { Entry(provider: $0, title: item.title, hint: item.hint) }
        }
    }

    static func title(forPrefix prefix: String) -> String? {
        (popular + servers).first { $0.prefix == prefix }?.title
    }

    static func isOAuth(_ prefix: String) -> Bool { oauthPrefixes.contains(prefix) }
}

/// A popular service: logo, plain name, and how signing in works.
private struct ProviderTile: View {
    let entry: PickerCatalog.Entry
    let onPick: () -> Void
    @State private var hovering = false
    @Environment(\.stratosphere) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: onPick) {
            VStack(spacing: 7) {
                LogoTile(provider: entry.provider.prefix)
                Text(verbatim: entry.title)
                    .font(DesignSystem.Stratosphere.Typography.label)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                if let hint = entry.hint {
                    Text(verbatim: hint)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(palette.textTertiary.color)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, DesignSystem.Spacing.s)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .contentShape(shape)
            .background(shape.fill(hovering ? palette.selection.color : palette.glassBottom.color))
            .overlay(shape.strokeBorder(hovering ? palette.actionTop.color : palette.glassBorder.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: [entry.title, entry.hint].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// A compact capsule for storage you run or rent, and for Import.
private struct ProviderChip: View {
    let title: String
    let prefix: String?
    let onPick: () -> Void
    @State private var hovering = false
    @Environment(\.stratosphere) private var palette

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 7) {
                if let prefix {
                    ProviderBadge(provider: prefix, size: 20)
                }
                Text(verbatim: title)
                    .font(DesignSystem.Stratosphere.Typography.control)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
            }
            .padding(.leading, prefix == nil ? 14 : 6)
            .padding(.trailing, 14)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? palette.selection.color : palette.glassBottom.color))
            .overlay(Capsule().strokeBorder(palette.glassBorder.color, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Lays children out left to right, wrapping to a new row when full.
struct FlowRows: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                                      proposal: .unspecified)
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var height: CGFloat = 0; var maxX: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].xs.append(x)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width
            rows[rows.count - 1].maxX = x
            x += spacing
        }
        return rows
    }
}

/// One provider row: flat brand badge, human-readable service name, and the
/// rclone backend id as the secondary line (the id is what power users type
/// into configs; the name is what everyone recognizes).
private struct ProviderRow: View {
    let provider: Provider
    let onPick: () -> Void
    @State private var hovering = false
    @Environment(\.stratosphere) private var palette

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: DesignSystem.Spacing.m) {
                ProviderBadge(provider: provider.prefix, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: provider.description)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(palette.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: provider.name)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(palette.textTertiary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Spacing.s)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Stratosphere.Radius.row, style: .continuous)
                    .fill(palette.selection.color)
                    .opacity(hovering ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(provider.description)
        .accessibilityHint(Text(verbatim: "rclone backend: \(provider.name)"))
    }
}

#if DEBUG
private func previewProvider(_ name: String, _ description: String) -> Provider {
    let json = #"{"Name":"\#(name)","Description":"\#(description)","Prefix":"\#(name)","Options":[]}"#
    return try! JSONDecoder().decode(Provider.self, from: Data(json.utf8))
}

private func previewProviders() -> [Provider] {
    var list: [Provider] = []
    list.append(previewProvider("drive", "Google Drive"))
    list.append(previewProvider("onedrive", "Microsoft OneDrive"))
    list.append(previewProvider("dropbox", "Dropbox"))
    list.append(previewProvider("iclouddrive", "iCloud Drive"))
    list.append(previewProvider("box", "Box"))
    list.append(previewProvider("pcloud", "Pcloud"))
    list.append(previewProvider("protondrive", "Proton Drive"))
    list.append(previewProvider("mega", "Mega"))
    list.append(previewProvider("s3", "Amazon S3 Compliant Storage Providers"))
    list.append(previewProvider("b2", "Backblaze B2"))
    list.append(previewProvider("sftp", "SSH/SFTP"))
    list.append(previewProvider("webdav", "WebDAV"))
    list.append(previewProvider("crypt", "Encrypt/Decrypt a remote"))
    list.append(previewProvider("ftp", "FTP"))
    return list
}

#Preview("Add Cloud, step 1", traits: .fixedLayout(width: 600, height: 760)) {
    SheetChrome(title: "Add Cloud", subtitle: nil, body: {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            SetupSteps(titles: ["Choose a service", "Name it", "Sign in"], current: 0)
            ProviderPicker(providers: previewProviders(), onPick: { _ in }, onImport: {})
        }
    }, actions: {
        Button("Cancel") {}.buttonStyle(.glassCapsule)
    })
    .preferredColorScheme(.dark)
}
#endif
