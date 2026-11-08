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
                                Image(systemName: line.isFailure ? "exclamationmark.circle" : "checkmark.circle")
                                    .foregroundStyle(line.isFailure ? DesignSystem.Color.semantic.statusError
                                                                    : DesignSystem.Color.semantic.textSecondary)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: line.text).lineLimit(1)
                                    Text(line.date, format: .relative(presentation: .named))
                                        .font(DesignSystem.Typography.caption2)
                                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
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
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: CompanionHeadline.title(for: summary.overall))
                    .font(DesignSystem.Typography.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignSystem.Spacing.s)
                headerAccessory
            }
            switch summary.overall {
            case .busy(let busy):
                ProgressView(value: busy.progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(verbatim: progressLine(busy))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Spacer()
                    Button("Show Transfers") { actions.showTransfers(busy.focusCloud) }
                        .controlSize(.small)
                }
            case .allReady:
                Text(verbatim: readyLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            case .noClouds:
                Text("Add one to see it here and in Finder.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            case .engineDown(let message):
                Text(verbatim: message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(3)
            case .needsAttention(let row):
                Text(verbatim: attentionLine(row))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
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
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
                .accessibilityHidden(true)
        case .starting:
            ProgressView().controlSize(.small)
        case .engineDown:
            Button("Restart", action: actions.restartEngine).controlSize(.small)
        case .noClouds:
            Button("Add Cloud", action: actions.addCloud)
                .buttonStyle(.borderedProminent).controlSize(.small)
        case .needsAttention(let row) where row.health == .needsSignIn:
            Button("Sign In") { actions.signIn(row) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        case .needsAttention(let row):
            Button(row.health == .failing ? "Show Details" : "Try Again") { actions.fix(row) }
                .controlSize(.small)
        case .busy:
            EmptyView()
        }
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
                .font(DesignSystem.Typography.captionEmphasized)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
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
            Spacer()
            Button("Open Nimbus", action: actions.openNimbus)
                .keyboardShortcut(.defaultAction)
            Menu {
                SettingsLink { Text("Settings…") }
                Toggle("Open at Login", isOn: $openAtLogin)
                Divider()
                Button("Quit Nimbus", action: actions.quit)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .controlSize(.small)
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
                    ProviderBadge(provider: row.providerType, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.name)
                            .font(DesignSystem.Typography.body)
                            .lineLimit(1)
                        Text(verbatim: detail)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(row.health == .needsSignIn
                                             ? DesignSystem.Color.semantic.statusWarning
                                             : DesignSystem.Color.semantic.textSecondary)
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
        .padding(.vertical, 4)
        .opacity(row.health == .unreachable ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(row.name), \(row.health == .ready ? "Ready, " : "")\(detail)"))
    }

    @ViewBuilder
    private var trailing: some View {
        switch row.health {
        case .needsSignIn:
            Button("Sign In", action: onSignIn)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .busy:
            ProgressView().controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
                .accessibilityHidden(true)
        case .failing:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusError)
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
            .background(.regularMaterial)
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
