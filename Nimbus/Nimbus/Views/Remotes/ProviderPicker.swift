import SwiftUI
import RcloneKit

/// Provider list for AddRemoteSheet. Reference: System Settings →
/// Internet Accounts — a dense, scannable list of badge · name · id rows,
/// popular services first. Rows, not tiles: with 50+ rclone backends the
/// text is the scan axis and the badge is a recognition aid, not the hero.
struct ProviderPicker: View {
    let providers: [Provider]
    let onPick: (Provider) -> Void
    @State private var search = ""

    /// The consumer services most users are actually adding, surfaced ahead
    /// of the alphabetical long tail. Order is deliberate (rough popularity),
    /// not alphabetical.
    private static let popularPrefixes = [
        "drive", "dropbox", "onedrive", "iclouddrive",
        "s3", "box", "mega", "protondrive",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            TextField("Search providers", text: $search)
                .textFieldStyle(.roundedBorder)

            if search.isEmpty {
                section("Popular", rows: popular)
                section("All Providers", rows: everythingElse)
            } else if filtered.isEmpty {
                Text("No providers match “\(search)”.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSystem.Spacing.xl)
            } else {
                rowStack(filtered)
            }
        }
    }

    // MARK: - Data

    private var popular: [Provider] {
        Self.popularPrefixes.compactMap { prefix in
            providers.first { $0.prefix == prefix }
        }
    }

    private var everythingElse: [Provider] {
        providers
            .filter { !Self.popularPrefixes.contains($0.prefix) }
            .sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }
    }

    private var filtered: [Provider] {
        let q = search.lowercased()
        return providers
            .filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
            .sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }
    }

    // MARK: - Layout

    @ViewBuilder
    private func section(_ title: String, rows: [Provider]) -> some View {
        if !rows.isEmpty {
            Text(verbatim: title)
                .font(DesignSystem.Typography.captionEmphasized)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .padding(.top, DesignSystem.Spacing.xs)
            rowStack(rows)
        }
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

/// One provider row: flat brand badge, human-readable service name, and the
/// rclone backend id as the secondary line (the id is what power users type
/// into configs; the name is what everyone recognizes).
private struct ProviderRow: View {
    let provider: Provider
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: DesignSystem.Spacing.m) {
                ProviderBadge(provider: provider.prefix, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: provider.description)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: provider.name)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Spacing.s)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
                    .opacity(hovering ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(provider.description)
        .accessibilityHint(Text(verbatim: "rclone backend: \(provider.name)"))
    }
}
