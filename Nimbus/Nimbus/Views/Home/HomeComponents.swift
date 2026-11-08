import SwiftUI

/// Distinct system colors for the aggregate bar, indexed by `CloudSummary.Row.tint`.
enum CloudTintPalette {
    static let colors: [Color] = [.blue, .teal, .indigo, .orange, .pink, .green, .yellow, .gray]
    static func color(_ slot: Int) -> Color { colors[min(max(slot, 0), colors.count - 1)] }
}

enum ByteText {
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// A grouped, inset container in System Settings' language: subtle fill,
/// continuous corners, hairline edge.
struct HomeGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .strokeBorder(DesignSystem.Color.semantic.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

struct HomeSectionTitle: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(DesignSystem.Typography.headline)
            .padding(.leading, DesignSystem.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Storage overview

struct StorageOverview: View {
    let summary: CloudSummary

    private var headline: String {
        let used = "\(ByteText.format(summary.usedBytes)) used"
        guard let free = summary.freeBytes else { return used }
        return "\(used), \(ByteText.format(free)) free"
    }

    var body: some View {
        HomeGroup {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("All your clouds").font(DesignSystem.Typography.headline)
                    Spacer()
                    Text(verbatim: headline)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                }
                StorageBar(summary: summary)
                    .frame(height: 22)
                legend
            }
            .padding(DesignSystem.Spacing.l)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), alignment: .leading)],
                  alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(summary.rows) { row in
                HStack(spacing: 6) {
                    Circle().fill(CloudTintPalette.color(row.tint)).frame(width: 8, height: 8)
                    Text(verbatim: row.name).fontWeight(.medium).lineLimit(1)
                    Text(verbatim: legendDetail(row))
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                        .lineLimit(1)
                }
                .font(DesignSystem.Typography.caption)
            }
        }
    }

    private func legendDetail(_ row: CloudSummary.Row) -> String {
        if let used = row.quota?.usedText {
            return row.quota?.total == nil ? "\(used), billed by use" : used
        }
        switch row.health {
        case .unreachable, .failing, .needsSignIn: return "not reachable"
        case .checking: return "checking…"
        case .ready, .busy: return "size not reported"
        }
    }

    private var accessibilityText: String {
        let parts = summary.rows.map { "\($0.name) \(legendDetail($0))" }
        return "All your clouds, \(headline). " + parts.joined(separator: ", ")
    }
}

struct StorageBar: View {
    let summary: CloudSummary

    var body: some View {
        GeometryReader { geo in
            let capacity = max(summary.capacityBytes, 1)
            let segments = summary.rows.compactMap { row -> (Int, Int64)? in
                guard let used = row.quota?.used, used > 0 else { return nil }
                return (row.tint, used)
            }
            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
            let usable = max(geo.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(CloudTintPalette.color(segment.0))
                        .frame(width: max(2, usable * CGFloat(segment.1) / CGFloat(capacity)))
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .background(DesignSystem.Color.semantic.separator.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(DesignSystem.Motion.smooth, value: summary.usedBytes)
        }
    }
}

// MARK: - Attention

struct AttentionBanner: View {
    let row: CloudSummary.Row
    let onFix: () -> Void

    private var tint: Color {
        row.health == .failing ? DesignSystem.Color.semantic.statusError : DesignSystem.Color.semantic.statusWarning
    }

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
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(DesignSystem.Typography.bodyEmphasized)
                Text(verbatim: message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            Button(buttonTitle, action: onFix)
                .buttonStyle(.borderedProminent)
                .tint(row.health == .failing ? nil : DesignSystem.Color.semantic.accent)
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

// MARK: - Cloud rows

struct HomeCloudRow: View {
    let row: CloudSummary.Row

    private var dotColor: Color {
        switch row.health {
        case .ready: DesignSystem.Color.semantic.statusOK
        case .busy: DesignSystem.Color.semantic.accent
        case .checking: DesignSystem.Color.semantic.textTertiary
        case .needsSignIn: DesignSystem.Color.semantic.statusWarning
        case .unreachable: DesignSystem.Color.semantic.statusMuted
        case .failing: DesignSystem.Color.semantic.statusError
        }
    }

    private var statusLine: String {
        if row.health == .unreachable, let last = row.lastConnected {
            return "\(row.sentence). Last connected \(last.formatted(.relative(presentation: .named)))."
        }
        return row.sentence
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            ProviderBadge(provider: row.providerType, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.name).font(DesignSystem.Typography.bodyEmphasized).lineLimit(1)
                HStack(spacing: 6) {
                    if row.health == .busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(dotColor).frame(width: 7, height: 7)
                    }
                    Text(verbatim: statusLine).lineLimit(1)
                    if row.isInFinder {
                        Text("In Finder")
                            .font(DesignSystem.Typography.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(DesignSystem.Color.semantic.separator.opacity(0.5)))
                    }
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            usage
                .frame(width: 150, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, DesignSystem.Spacing.m)
        .contentShape(Rectangle())
        .opacity(row.health == .unreachable ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.name), \(row.providerName), \(statusLine)\(row.isInFinder ? ", in Finder" : ""), \(usageText ?? "")"))
        .accessibilityAddTraits(.isButton)
    }

    private var usageText: String? {
        guard let quota = row.quota, let used = quota.usedText else { return nil }
        if let total = quota.totalText { return "\(used) of \(total)" }
        return used
    }

    @ViewBuilder
    private var usage: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let quota = row.quota, let used = quota.usedText {
                if let total = quota.totalText, let fraction = quota.fraction {
                    Text(verbatim: "\(used) of \(total)")
                    CapacityBar(fraction: fraction, isNearlyFull: quota.isNearlyFull)
                } else {
                    Text(verbatim: used)
                    Text("Billed by what you store")
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                }
            }
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
    }
}

// MARK: - Suggestions and activity

struct SuggestionView: View {
    let suggestion: CloudSummary.Suggestion
    let onAct: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title).font(DesignSystem.Typography.bodyEmphasized)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .help("Don't show this again")
                .accessibilityLabel("Dismiss suggestion")
            }
            Text(verbatim: message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: onAct)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(DesignSystem.Spacing.m)
    }

    private var title: String {
        switch suggestion {
        case .nearlyFull(let row): "\(row.name) is almost full"
        case .notInFinder(let row): "\(row.name) isn't in Finder yet"
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
        }
    }

    private var buttonTitle: String {
        switch suggestion {
        case .nearlyFull(let row): "Open \(row.name)"
        case .notInFinder: "Show in Finder"
        }
    }
}

struct ActivityRow: View {
    let line: ActivityLine

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: line.isFailure ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(line.isFailure ? DesignSystem.Color.semantic.statusError : DesignSystem.Color.semantic.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: line.text).lineLimit(2)
                Text(line.date, format: .relative(presentation: .named))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .font(DesignSystem.Typography.caption)
        .padding(.horizontal, DesignSystem.Spacing.m)
        .padding(.vertical, DesignSystem.Spacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
