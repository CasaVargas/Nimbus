import SwiftUI

/// A finished comparison: a tile per group with its count, and the files in
/// the chosen group. Read-only; nothing here changes either folder.
struct CompareResultsView: View {
    enum Group: Hashable, CaseIterable {
        case differ, onlyInA, onlyInB, errors, same
    }

    let result: CompareResult
    let nameA: String
    let nameB: String

    @State private var group: Group = .differ
    @Environment(\.stratosphere) private var palette

    private typealias S = DesignSystem.Stratosphere

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            if result.comparedWithoutHash {
                DestructiveCallout(message: "These two places share no checksum type, so Nimbus compared sizes only. Files with the same size but different content show as the same.")
            }
            if result.matches {
                matchBanner
            }
            tiles
            pathList
        }
        .onChange(of: result, initial: true) { group = Self.firstGroup(in: result) }
    }

    /// The first group worth looking at: differences before matches.
    static func firstGroup(in result: CompareResult) -> Group {
        Group.allCases.first { !paths(for: $0, in: result).isEmpty } ?? .same
    }

    static func paths(for group: Group, in result: CompareResult) -> [String] {
        switch group {
        case .same: result.same
        case .differ: result.differ
        case .onlyInA: result.onlyInA
        case .onlyInB: result.onlyInB
        case .errors: result.errors
        }
    }

    private var matchBanner: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            IconTile(systemImage: "checkmark", color: S.CloudColors.backups, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("These folders match")
                    .font(S.Typography.sectionTitle)
                    .foregroundStyle(palette.textPrimary.color)
                Text("\(result.same.count) files are the same in both places.")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.m)
        .glassSurface(radius: S.Radius.card, tint: S.CloudColors.backups)
        .accessibilityElement(children: .combine)
    }

    private var visibleGroups: [Group] {
        Group.allCases.filter { $0 != .errors || !result.errors.isEmpty }
    }

    private var tiles: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            ForEach(visibleGroups, id: \.self) { item in
                tile(item)
            }
        }
    }

    private func tile(_ item: Group) -> some View {
        let style = Self.style(for: item, nameA: nameA, nameB: nameB)
        let count = Self.paths(for: item, in: result).count
        let isSelected = item == group
        return Button {
            group = item
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                HStack {
                    IconTile(systemImage: style.symbol, color: style.color, size: 26)
                    Spacer(minLength: 0)
                    Text(count, format: .number)
                        .font(S.Typography.sheetTitle)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title)
                        .font(S.Typography.segment)
                        .foregroundStyle(palette.textPrimary.color)
                    Text(verbatim: style.detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(DesignSystem.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassSurface(radius: S.Radius.card, tint: isSelected ? style.color : nil)
            .overlay {
                RoundedRectangle(cornerRadius: S.Radius.card, style: .continuous)
                    .strokeBorder(style.color.end.color.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(style.title), \(count) files"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var pathList: some View {
        let paths = Self.paths(for: group, in: result)
        return List(paths, id: \.self) { path in
            Label {
                Text(verbatim: path)
                    .font(S.Typography.detail)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "doc")
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .glassContentSurface()
        .frame(minHeight: 260)
        .overlay {
            if paths.isEmpty {
                Text("None")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
        .accessibilityLabel(Text(Self.style(for: group, nameA: nameA, nameB: nameB).title))
    }

    struct Style {
        let title: LocalizedStringKey
        let detail: String
        let symbol: String
        let color: DesignSystem.Stratosphere.CloudColor
    }

    static func style(for group: Group, nameA: String, nameB: String) -> Style {
        switch group {
        case .differ:
            Style(title: "Different", detail: String(localized: "Changed on one side"),
                  symbol: "notequal", color: S.CloudColors.nearlyFull)
        case .onlyInA:
            Style(title: "Only in A", detail: nameA, symbol: "a.circle", color: S.CloudColors.home)
        case .onlyInB:
            Style(title: "Only in B", detail: nameB, symbol: "b.circle", color: S.CloudColors.copy)
        case .errors:
            Style(title: "Couldn't Read", detail: String(localized: "Check these files"),
                  symbol: "exclamationmark", color: S.CloudColors.sequence[2])
        case .same:
            Style(title: "Same", detail: String(localized: "In both places"),
                  symbol: "equal", color: S.CloudColors.backups)
        }
    }
}

#Preview("Differences") {
    CompareResultsView(
        result: CompareResult(combined: [
            "= Photos/2024/beach.jpg", "= Photos/2024/hike.jpg", "= Notes.md",
            "* Taxes/2025 return.pdf", "* Budget.numbers",
            "+ Projects/Nimbus/spec.md", "+ Projects/Nimbus/plan.md", "+ Inbox/receipt.png",
            "- Old/archive.zip",
        ]),
        nameA: "Documents", nameB: "gdrive: Backup/Documents"
    )
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 860, height: 560)
    .background { StratosphereBackdrop() }
    .preferredColorScheme(.dark)
}

#Preview("Match, no hash") {
    CompareResultsView(
        result: CompareResult(combined: ["= a.txt", "= b.txt"], comparedWithoutHash: true),
        nameA: "Documents", nameB: "b2: mac/Documents"
    )
    .padding(DesignSystem.Spacing.xl)
    .frame(width: 860, height: 560)
    .background { StratosphereBackdrop() }
    .preferredColorScheme(.dark)
}
