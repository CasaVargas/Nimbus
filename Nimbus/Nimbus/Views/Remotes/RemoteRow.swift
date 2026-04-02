import SwiftUI
import RcloneKit

struct RemoteRow: View {
    let remote: Remote
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName(for: remote.type))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(remote.name)
                    .font(.headline)
                Text(remote.type)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onBrowse()
            } label: {
                Label("Browse", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .onHover { _ in } // Ensures button is independently hittable in List
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Browse") { onBrowse() }
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "drive": "cloud"
        case "s3": "shippingbox"
        case "dropbox": "drop"
        case "onedrive": "cloud"
        case "sftp", "ftp": "server.rack"
        case "local": "folder"
        default: "cloud"
        }
    }
}
