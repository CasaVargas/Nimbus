import SwiftUI

struct MountRow: View {
    let config: MountConfig
    let isActive: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isActive ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(config.remote)
                    .font(.headline)
                Text(config.mountPoint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(config.vfsMode.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text(config.backend.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            Spacer()

            Button(isActive ? "Unmount" : "Mount") {
                onToggle()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Remove", role: .destructive) { onRemove() }
        }
    }
}
