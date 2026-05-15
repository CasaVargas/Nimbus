import SwiftUI
import RcloneKit

/// Grid of provider tiles for picking a remote type in AddRemoteSheet.
/// Reference: System Settings → Add Account provider picker.
struct ProviderPicker: View {
    let providers: [Provider]
    let onPick: (Provider) -> Void
    @State private var search = ""

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: DesignSystem.Spacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            TextField("Search providers", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.m) {
                    ForEach(filtered, id: \.name) { provider in
                        tile(for: provider)
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.s)
            }
        }
    }

    private var filtered: [Provider] {
        guard !search.isEmpty else { return providers }
        let q = search.lowercased()
        return providers.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func tile(for provider: Provider) -> some View {
        Button {
            onPick(provider)
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon(for: provider.name))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                Text(verbatim: provider.name)
                    .font(DesignSystem.Typography.caption)
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            }
            .frame(width: 96, height: 96)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.name)
        .accessibilityHint(provider.description)
    }

    private func icon(for providerName: String) -> String {
        switch providerName.lowercased() {
        case "drive", "google drive": return "externaldrive.connected.to.line.below"
        case "s3", "amazon s3": return "shippingbox"
        case "b2", "backblaze": return "shippingbox"
        case "dropbox": return "drop"
        case "onedrive", "sharepoint": return "cloud"
        case "sftp", "ftp": return "server.rack"
        case "local": return "folder"
        case "crypt": return "lock.shield"
        case "webdav": return "globe"
        case "azureblob", "azure": return "cloud.fill"
        case "box": return "shippingbox.fill"
        case "pcloud", "mega", "mailru": return "cloud"
        default: return "cloud"
        }
    }
}
