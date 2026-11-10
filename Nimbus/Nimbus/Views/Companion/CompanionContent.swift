import SwiftUI

/// Everything the companion can ask its owner to do.
struct CompanionActions {
    var openCloud: (String) -> Void = { _ in }
    var signIn: (CloudSummary.Row) -> Void = { _ in }
    var fix: (CloudSummary.Row) -> Void = { _ in }
    var showTransfers: (String?) -> Void = { _ in }
    var addCloud: () -> Void = {}
    var openNimbus: () -> Void = {}
    var restartEngine: () -> Void = {}
    var quit: () -> Void = {}
}

/// The menu bar window, rendered from data only: what's happening now, each
/// cloud in one line, the last few finished copies, and the way into the app.
struct CompanionContent: View {
    let summary: CloudSummary
    let activity: [ActivityLine]
    @Binding var openAtLogin: Bool
    var actions = CompanionActions()

    static let width: CGFloat = 340

    @Environment(\.stratosphere) private var palette
    @Environment(\.cloudColors) private var cloudColors

    private typealias S = DesignSystem.Stratosphere

    /// True when the header already offers the one thing to do next (sign
    /// in, add a cloud, restart). Open Nimbus then steps back to a glass
    /// capsule so the panel keeps a single filled button.
    private var headerHasPrimaryAction: Bool {
        switch summary.overall {
        case .noClouds, .needsAttention, .engineDown: true
        case .starting, .allReady, .busy: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !summary.rows.isEmpty {
                Divider()
                section("Clouds") {
                    ForEach(summary.rows) { row in
                        CompanionCloudRow(row: row, onOpen: { actions.openCloud(row.name) },
                                          onSignIn: { actions.signIn(row) })
                    }
                }
            }
            if !activity.isEmpty {
                Divider()
                section("Recent activity") {
                    ForEach(activity.prefix(3)) { line in
                        Button { actions.openCloud(line.cloud) } label: {
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
                                Image(systemName: line.isFailure ? "exclamationmark.triangle" : "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(line.isFailure ? palette.error.color : palette.ok.color)
                                    .frame(width: 34)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: line.text)
                                        .foregroundStyle(palette.textPrimary.color)
                                        .lineLimit(1)
                                    Text(line.date, format: .relative(presentation: .named))
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(palette.textTertiary.color)
                                }
                                Spacer(minLength: 0)
                            }
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, DesignSystem.Spacing.s)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: Self.width)
        .background(LinearGradient(colors: [palette.sheetTop.color, palette.sheetBottom.color],
                                   startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: CompanionHeadline.title(for: summary.overall))
                    .font(S.Typography.sectionTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignSystem.Spacing.s)
                headerAccessory
            }
            switch summary.overall {
            case .busy(let busy):
                UsageBar(fraction: busy.progress, color: busyColor(busy), height: 10)
                HStack {
                    Text(verbatim: progressLine(busy))
                        .font(S.Typography.detail)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary.color)
                    Spacer()
                    Button("Show Transfers") { actions.showTransfers(busy.focusCloud) }
                        .buttonStyle(.glassCapsule)
                }
            case .allReady:
                Text(verbatim: readyLine)
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
            case .noClouds:
                Text("Add one to see it here and in Finder.")
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
            case .engineDown(let message):
                Text(verbatim: message)
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(3)
            case .needsAttention(let row):
                Text(verbatim: attentionLine(row))
                    .font(S.Typography.detail)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            case .starting:
                EmptyView()
            }
        }
        .padding(DesignSystem.Spacing.l)
    }

    @ViewBuilder
    private var headerAccessory: some View {
        switch summary.overall {
        case .allReady:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.ok.color)
                .accessibilityHidden(true)
        case .starting:
            ProgressView().controlSize(.small)
        case .engineDown:
            Button("Restart", action: actions.restartEngine).buttonStyle(.primaryPill(.small))
        case .noClouds:
            Button("Add Cloud", action: actions.addCloud)
                .buttonStyle(.primaryPill(.small))
        case .needsAttention(let row) where row.health == .needsSignIn:
            Button("Sign In") { actions.signIn(row) }
                .buttonStyle(.primaryPill(.small))
        case .needsAttention(let row):
            Button(row.health == .failing ? "Show Details" : "Try Again") { actions.fix(row) }
                .buttonStyle(.primaryPill(.small))
        case .busy:
            EmptyView()
        }
    }

    /// The bar takes the colour of the cloud the transfer is headed to.
    private func busyColor(_ busy: CloudSummary.Busy) -> S.CloudColor {
        guard let name = busy.focusCloud, let row = summary.rows.first(where: { $0.name == name }) else {
            return S.CloudColors.home
        }
        return row.color(in: cloudColors)
    }

    private var readyLine: String {
        summary.rows.count == 1 ? "1 cloud, nothing waiting on you." : "\(summary.rows.count) clouds, nothing waiting on you."
    }

    private func progressLine(_ busy: CloudSummary.Busy) -> String {
        let percent = "\(Int((busy.progress * 100).rounded()))% done"
        guard let eta = busy.eta else { return percent }
        return "\(percent), about \(CloudSummaryBuilder.etaText(eta)) left"
    }

    private func attentionLine(_ row: CloudSummary.Row) -> String {
        switch row.health {
        case .needsSignIn: "\(row.providerName) ended the session. New changes wait until you sign in."
        case .failing: row.errorDetail.map { $0.split(whereSeparator: \.isNewline).first.map(String.init) ?? $0 } ?? "Open it to see what went wrong."
        default: "If it's on your home network, it reconnects when you're back."
        }
    }

    // MARK: - Sections and footer

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(S.Typography.segment)
                .foregroundStyle(palette.textTertiary.color)
                .padding(.horizontal, DesignSystem.Spacing.s)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, DesignSystem.Spacing.s)
        .padding(.vertical, DesignSystem.Spacing.s)
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Button("Add Cloud…", action: actions.addCloud)
                .buttonStyle(.glassCapsule)
            Spacer()
            if headerHasPrimaryAction {
                Button("Open Nimbus", action: actions.openNimbus)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassCapsule)
            } else {
                Button("Open Nimbus", action: actions.openNimbus)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryPill(.small))
            }
            Menu {
                SettingsLink { Text("Settings…") }
                Toggle("Open at Login", isOn: $openAtLogin)
                Divider()
                Button("Quit Nimbus", action: actions.quit)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(palette.textPrimary.color)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, DesignSystem.Spacing.l)
        .padding(.vertical, DesignSystem.Spacing.m)
    }
}

/// One cloud in the companion: badge, name, one line of status, and the one
/// action that matters for its state.
struct CompanionCloudRow: View {
    let row: CloudSummary.Row
    let onOpen: () -> Void
    let onSignIn: () -> Void

    @Environment(\.stratosphere) private var palette

    private var detail: String {
        if row.health == .ready, let quota = row.quota, let used = quota.usedText {
            if let total = quota.totalText { return "\(used) of \(total)" }
            return "\(used) stored"
        }
        return row.sentence
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Button(action: onOpen) {
                HStack(spacing: DesignSystem.Spacing.s) {
                    LogoTile(provider: row.providerType, size: .compact)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.name)
                            .font(DesignSystem.Stratosphere.Typography.label)
                            .foregroundStyle(palette.textPrimary.color)
                            .lineLimit(1)
                        Text(verbatim: detail)
                            .font(DesignSystem.Stratosphere.Typography.detail)
                            .monospacedDigit()
                            .foregroundStyle(row.health == .needsSignIn ? palette.warning.color
                                                                        : palette.textSecondary.color)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing
        }
        .padding(.horizontal, DesignSystem.Spacing.s)
        .padding(.vertical, 5)
        .opacity(row.health == .unreachable ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(row.name), \(row.health == .ready ? "Ready, " : "")\(detail)"))
    }

    @ViewBuilder
    private var trailing: some View {
        switch row.health {
        case .needsSignIn:
            // The header carries the filled Sign In; this one stays quiet.
            Button("Sign In", action: onSignIn)
                .buttonStyle(.glassCapsule)
        case .busy:
            ProgressView().controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.ok.color)
                .accessibilityHidden(true)
        case .failing:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(palette.error.color)
                .accessibilityHidden(true)
        case .checking, .unreachable:
            EmptyView()
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct CompanionPreview: View {
    let summary: CloudSummary
    var activity: [ActivityLine] = HomePreviewData.activity
    @State private var openAtLogin = true

    var body: some View {
        CompanionContent(summary: summary, activity: activity, openAtLogin: $openAtLogin)
            .preferredColorScheme(.dark)
    }
}

private enum CompanionPreviewData {
    static let dropboxReady = HomePreviewData.row("Dropbox", "dropbox", "Dropbox", .ready, "Ready",
                                                  used: 61 * HomePreviewData.gb, total: 2 * HomePreviewData.tb, tint: 2)
    static let busyRows = [HomePreviewData.personal, HomePreviewData.workReady, HomePreviewData.dropbox,
                           HomePreviewData.archive, HomePreviewData.nas]
    static let readyRows = [HomePreviewData.personal, HomePreviewData.workReady, dropboxReady, HomePreviewData.archive]
}

#Preview("Busy") {
    CompanionPreview(summary: HomePreviewData.summary(
        CompanionPreviewData.busyRows,
        overall: .busy(.init(progress: 0.34, sentence: "Copying 3 items to Dropbox", direction: .up,
                             focusCloud: "Dropbox", eta: 130))))
}

#Preview("Needs sign-in") {
    let rows = [HomePreviewData.personal, HomePreviewData.work, CompanionPreviewData.dropboxReady, HomePreviewData.nas]
    CompanionPreview(summary: HomePreviewData.summary(rows, overall: .needsAttention(HomePreviewData.work),
                                                      attention: HomePreviewData.work))
}

#Preview("All ready") {
    CompanionPreview(summary: HomePreviewData.summary(CompanionPreviewData.readyRows, overall: .allReady), activity: [])
}

#Preview("No clouds") {
    CompanionPreview(summary: HomePreviewData.summary([], overall: .noClouds), activity: [])
}

#Preview("Engine down") {
    CompanionPreview(summary: HomePreviewData.summary([], overall: .engineDown("rclone exited with status 1")), activity: [])
}
#endif
