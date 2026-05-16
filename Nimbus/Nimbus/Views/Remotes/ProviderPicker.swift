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

            // No ScrollView here: SheetChrome already scrolls the body.
            // A nested ScrollView reports unbounded height and balloons the sheet.
            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.m) {
                ForEach(filtered, id: \.name) { provider in
                    tile(for: provider)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.s)
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
        ProviderTile(provider: provider, onPick: { onPick(provider) })
    }
}

/// Single app-icon-style provider tile with a hover lift + ring.
private struct ProviderTile: View {
    let provider: Provider
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: DesignSystem.Spacing.s) {
                ProviderBadge(provider: provider.prefix, size: 52)
                Text(verbatim: provider.name)
                    .font(DesignSystem.Typography.caption)
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            }
            .frame(width: 104, height: 104)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
                    .opacity(hovering ? 1 : 0.55)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .strokeBorder(
                        DesignSystem.Color.semantic.accent.opacity(hovering ? 0.55 : 0),
                        lineWidth: 1
                    )
            )
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.snappy(duration: 0.14), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(provider.name)
        .accessibilityHint(provider.description)
    }
}
