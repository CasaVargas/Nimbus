import SwiftUI

enum ByteText {
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private typealias S = DesignSystem.Stratosphere

/// A glass group: Home's lists and tips sit on these.
struct HomeGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .glassSurface(radius: S.Radius.card)
    }
}

struct HomeSectionTitle: View {
    let text: String
    @Environment(\.stratosphere) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(S.Typography.sectionTitle)
            .foregroundStyle(palette.textPrimary.color)
            .padding(.leading, DesignSystem.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

extension CloudSummary.Row {
    /// This cloud's colour: the window's assignment, or its provider's
    /// colour where no window assigned one (previews, the menu bar).
    func color(in assigned: [String: DesignSystem.Stratosphere.CloudColor]) -> DesignSystem.Stratosphere.CloudColor {
        assigned[name] ?? DesignSystem.Stratosphere.CloudColors.color(forProvider: providerType)
    }

    var stratosphereStatus: StratosphereStatus {
        switch health {
        case .ready, .busy: .ok
        case .needsSignIn: .warning
        case .checking, .unreachable: .muted
        case .failing: .error
        }
    }
}

// MARK: - Hero

/// The top of Home: how much room there is, one sentence on how things
/// stand, and every cloud's share of storage as a ring.
struct HomeHero: View {
    let summary: CloudSummary
    /// True when nothing else on the screen is asking for a click, so Add
    /// Cloud may be the filled button. With an attention banner showing,
    /// the banner's fix is the primary action and this one goes quiet.
    let addCloudIsPrimary: Bool
    let isWide: Bool
    let onAddCloud: () -> Void

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors

    private var totals: StorageTotals { StorageTotals(quotas: summary.rows.compactMap(\.quota)) }

    var body: some View {
        Group {
            if isWide {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.xl) {
                    words
                    Spacer(minLength: 0)
                    if totals.usedFraction != nil {
                        ring.frame(width: 204, height: 204)
                        legend.frame(width: 200)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    words
                    if totals.usedFraction != nil {
                        HStack(spacing: DesignSystem.Spacing.xl) {
                            ring.frame(width: 160, height: 160)
                            legend
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                Text("All your clouds")
                    .font(S.Typography.label)
                    .foregroundStyle(palette.textSecondary.color)
                Text(verbatim: HomeHeadline.title(for: summary))
                    .font(S.Typography.hero)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: HomeHeadline.sentence(for: summary))
                    .font(S.Typography.lead)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if addCloudIsPrimary {
                Button(action: onAddCloud) { Label("Add Cloud", systemImage: "plus") }
                    .buttonStyle(.primaryPill)
            } else {
                Button(action: onAddCloud) { Label("Add Cloud", systemImage: "plus") }
                    .buttonStyle(.glassCapsule)
            }
        }
    }

    private var ring: some View {
        StorageRing(
            segments: summary.rows.compactMap { row -> StorageRingSegment? in
                guard let quota = row.quota else { return nil }
                return StorageRingSegment(id: row.id, fraction: totals.share(of: quota),
                                          color: row.color(in: cloudColors))
            },
            accessibilityLabel: Text(verbatim: ringSummary)
        ) {
            VStack(spacing: 2) {
                if let fraction = totals.usedFraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(S.Typography.ringValue)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary.color)
                        // Never wrap "34%" onto two lines, however narrow
                        // the caption under it is.
                        .lineLimit(1)
                        .fixedSize()
                }
                // Short on purpose: the full sentence doesn't fit inside the
                // ring at its smaller size. The headline already says what's
                // used; this adds what it's out of.
                Text(verbatim: "of \(ByteText.format(totals.capacityBytes))")
                    .font(S.Typography.detail)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var ringSummary: String {
        "\(ByteText.format(totals.usedBytes)) of \(ByteText.format(totals.capacityBytes)) used"
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(summary.rows) { row in
                legendRow(
                    swatch: row.quota?.used == nil ? palette.track.color : row.color(in: cloudColors).start.color,
                    name: row.name,
                    detail: Self.legendDetail(row)
                )
            }
            if let free = totals.freeBytes {
                legendRow(swatch: palette.track.color, name: "Free", detail: ByteText.format(free))
            }
        }
    }

    private func legendRow(swatch: Color, name: String, detail: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatch)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(S.Typography.label)
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
            Spacer(minLength: DesignSystem.Spacing.s)
            Text(verbatim: detail)
                .font(S.Typography.detail)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary.color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    static func legendDetail(_ row: CloudSummary.Row) -> String {
        if let used = row.quota?.usedText { return used }
        switch row.health {
        case .unreachable, .failing, .needsSignIn: return "not reachable"
        case .checking: return "checking…"
        case .ready, .busy: return "size not reported"
        }
    }
}

// MARK: - Attention

struct AttentionBanner: View {
    let row: CloudSummary.Row
    let onFix: () -> Void

    @Environment(\.stratosphere) private var palette

    private var isFailure: Bool { row.health == .failing }

    private var tint: Color { isFailure ? palette.error.color : palette.warning.color }

    private var title: String {
        switch row.health {
        case .needsSignIn: "\(row.name) needs you to sign in again"
        case .failing: "Nimbus can't connect to \(row.name)"
        default:
            if let last = row.lastConnected {
                "\(row.name) has been unreachable since \(last.formatted(.dateTime.weekday(.wide).month().day()))"
            } else {
                "\(row.name) can't be reached"
            }
        }
    }

    private var message: String {
        switch row.health {
        case .needsSignIn:
            "\(row.providerName) ended the session. Files already on this Mac are safe; new changes wait until you sign in."
        case .failing:
            row.errorDetail.map { firstLine($0) } ?? "Open it to see what went wrong."
        default:
            "If it's on your home network, it reconnects when you're back."
        }
    }

    private var buttonTitle: String {
        switch row.health {
        case .needsSignIn: "Sign In to \(row.providerName)"
        case .failing: "Show Details"
        default: "Try Again"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: DesignSystem.Spacing.m) {
            Circle()
                .fill(tint)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "exclamationmark")
                        .font(DesignSystem.Typography.bodyEmphasized)
                        .foregroundStyle(.black.opacity(0.75))
                }
                .shadow(color: tint.opacity(0.5), radius: 9, y: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(DesignSystem.Typography.bodyEmphasized)
                    .foregroundStyle(palette.textPrimary.color)
                Text(verbatim: message)
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            Button(buttonTitle, action: onFix)
                .buttonStyle(.primaryPill(.small))
        }
        .padding(.leading, 14)
        .padding(.trailing, DesignSystem.Spacing.m)
        .padding(.vertical, 11)
        .background {
            shape.fill(LinearGradient(
                colors: [tint.opacity(0.30), tint.opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            ))
        }
        .overlay(shape.strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

// MARK: - Cloud cards

/// One cloud on Home: its logo, name, a sentence on how it's doing, and how
/// full it is. The whole card opens the cloud.
struct HomeCloudCard: View {
    let row: CloudSummary.Row

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors

    private var statusLine: String {
        if row.health == .unreachable, let last = row.lastConnected {
            return Self.keepingNumbersWithUnits(
                "\(row.sentence). Last connected \(last.formatted(.relative(presentation: .named))).")
        }
        return Self.keepingNumbersWithUnits(row.sentence)
    }

    /// Joins a number to the word after it with a no-break space, so a
    /// narrow card wraps "Uploading 3 items, / 2 min left" and never
    /// "… 2 / min left".
    nonisolated static func keepingNumbersWithUnits(_ text: String) -> String {
        text.replacing(/(\d) (\p{L})/) { match in "\(match.1)\u{00A0}\(match.2)" }
    }

    private var usageText: String? {
        guard let quota = row.quota, let used = quota.usedText else { return nil }
        if let total = quota.totalText { return "\(used) of \(total)" }
        return "\(used), billed by use"
    }

    var body: some View {
        let color = row.color(in: cloudColors)
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(alignment: .top) {
                LogoTile(provider: row.providerType)
                Spacer(minLength: 0)
                if row.isInFinder {
                    Chip(text: Text("In Finder"))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.name)
                    .font(S.Typography.sectionTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if row.health == .busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        StatusDot(status: row.stratosphereStatus)
                    }
                    Text(verbatim: statusLine)
                        .font(S.Typography.detail)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let quota = row.quota, let fraction = quota.fraction {
                UsageBar(fraction: fraction,
                         color: quota.isNearlyFull ? DesignSystem.Stratosphere.CloudColors.nearlyFull : color)
            }
            if let usageText {
                Text(verbatim: usageText)
                    .font(S.Typography.detail)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(alignment: .topLeading) {
            // The cloud's colour, as a glow behind its logo.
            Circle()
                .fill(RadialGradient(colors: [color.start.color.opacity(0.55), color.start.color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 80))
                .frame(width: 160, height: 160)
                .offset(x: -50, y: -60)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: S.Radius.card, style: .continuous))
        .glassSurface(radius: S.Radius.card)
        .contentShape(RoundedRectangle(cornerRadius: S.Radius.card, style: .continuous))
        .opacity(row.health == .unreachable ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.name), \(row.providerName), \(statusLine)\(row.isInFinder ? ", in Finder" : ""), \(usageText ?? "")"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Suggestions and activity

struct SuggestionView: View {
    let suggestion: CloudSummary.Suggestion
    let onAct: () -> Void
    let onDismiss: () -> Void

    @Environment(\.stratosphere) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(DesignSystem.Typography.bodyEmphasized)
                    .foregroundStyle(palette.textPrimary.color)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.textTertiary.color)
                .help("Don't show this again")
                .accessibilityLabel("Dismiss suggestion")
            }
            Text(verbatim: message)
                .font(S.Typography.detail)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: onAct)
                .buttonStyle(.glassCapsule)
                .padding(.top, 4)
        }
        .padding(DesignSystem.Spacing.m)
    }

    private var title: String {
        switch suggestion {
        case .nearlyFull(let row): "\(row.name) is almost full"
        case .notInFinder(let row): "\(row.name) isn't in Finder yet"
        case .backup(let note): note.sentence
        }
    }

    private var message: String {
        switch suggestion {
        case .nearlyFull(let row):
            if let free = row.quota?.freeText, let total = row.quota?.totalText {
                "\(free) left of \(total)."
            } else {
                "There's very little space left."
            }
        case .notInFinder:
            "Show it under Locations so you can open its files from any app."
        case .backup(let note):
            switch note.kind {
            case .stopped: "It would have removed more files than its limit allows. Review it, then approve it to continue."
            case .failed: "See what went wrong and run it again."
            case .hasntRun: "Check its schedule or back up now."
            }
        }
    }

    private var buttonTitle: String {
        switch suggestion {
        case .nearlyFull(let row): "Open \(row.name)"
        case .notInFinder: "Show in Finder"
        case .backup: "Open Backups"
        }
    }
}

struct ActivityRow: View {
    let line: ActivityLine

    @Environment(\.stratosphere) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.s) {
            Image(systemName: line.isFailure ? "exclamationmark.triangle" : "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(line.isFailure ? palette.error.color : palette.ok.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(verbatim: line.text)
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(2)
            Spacer(minLength: DesignSystem.Spacing.s)
            Text(line.date, format: .relative(presentation: .named))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
        }
        .font(S.Typography.detail)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
