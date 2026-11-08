import SwiftUI

/// Everything Home can ask its owner to do. Closures, so `HomeContent` stays
/// a pure function of `CloudSummary` and previews need no live services.
struct HomeActions {
    var openCloud: (String) -> Void = { _ in }
    var fix: (CloudSummary.Row) -> Void = { _ in }
    var act: (CloudSummary.Suggestion) -> Void = { _ in }
    var dismiss: (CloudSummary.Suggestion) -> Void = { _ in }
    var showInFinder: (String) -> Void = { _ in }
    var openInFinder: (String) -> Void = { _ in }
    var signIn: (CloudSummary.Row) -> Void = { _ in }
    var copyBetweenClouds: () -> Void = {}
    var addCloud: () -> Void = {}
    var restartEngine: () -> Void = {}
}

/// Home's body, rendered from data only.
struct HomeContent: View {
    let summary: CloudSummary
    let activity: [ActivityLine]
    let providerCount: Int
    var actions = HomeActions()

    @State private var width: CGFloat = 900

    var body: some View {
        switch summary.overall {
        case .starting:
            VStack(spacing: DesignSystem.Spacing.m) {
                ProgressView().controlSize(.large)
                Text("Starting…").foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .engineDown(let message):
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Nimbus's connection engine stopped",
                messageVerbatim: message,
                action: .init(label: "Restart", perform: actions.restartEngine)
            )
        case .noClouds:
            noClouds
        case .allReady, .busy, .needsAttention:
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                StorageOverview(summary: summary)
                if let row = summary.attention {
                    AttentionBanner(row: row, onFix: { actions.fix(row) })
                        .transition(.opacity)
                }
                if width >= 820 {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.xl) {
                        cloudList.frame(maxWidth: .infinity)
                        sideColumn.frame(width: 270)
                    }
                } else {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                        cloudList
                        sideColumn
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xl + 4)
            .padding(.vertical, DesignSystem.Spacing.l)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .animation(DesignSystem.Motion.smooth, value: summary.attention?.id)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var cloudList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            HomeSectionTitle(text: "Your clouds")
            HomeGroup {
                ForEach(Array(summary.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 64) }
                    Button { actions.openCloud(row.name) } label: { HomeCloudRow(row: row) }
                        .buttonStyle(.plain)
                        .contextMenu { rowMenu(row) }
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ row: CloudSummary.Row) -> some View {
        Button("Open \(row.name)") { actions.openCloud(row.name) }
        if row.isInFinder {
            Button("Open in Finder") { actions.openInFinder(row.name) }
        } else {
            Button("Show in Finder") { actions.showInFinder(row.name) }
        }
        if row.health == .needsSignIn {
            Button("Sign In to \(row.providerName)…") { actions.signIn(row) }
        }
        Divider()
        Button("Copy Between Clouds…", action: actions.copyBetweenClouds)
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            if !summary.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                    HomeSectionTitle(text: "Worth a look")
                    HomeGroup {
                        ForEach(Array(summary.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            if index > 0 { Divider() }
                            SuggestionView(
                                suggestion: suggestion,
                                onAct: { actions.act(suggestion) },
                                onDismiss: { actions.dismiss(suggestion) }
                            )
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
                HomeSectionTitle(text: "Recent activity")
                HomeGroup {
                    if activity.isEmpty {
                        Text("Copies and moves between clouds show up here.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                            .padding(DesignSystem.Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(activity.enumerated()), id: \.element.id) { index, line in
                            if index > 0 { Divider() }
                            Button { actions.openCloud(line.cloud) } label: { ActivityRow(line: line) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var noClouds: some View {
        VStack(spacing: DesignSystem.Spacing.l) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Add your first cloud")
                .font(DesignSystem.Typography.titleEmphasized)
            Text(verbatim: noCloudsMessage)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Add Cloud", action: actions.addCloud)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noCloudsMessage: String {
        let more = providerCount > 4 ? " and \(providerCount - 4) more services" : ""
        return "Google Drive, Dropbox, OneDrive, your own server\(more). You sign in on each service's own page."
    }
}

// MARK: - Previews

#if DEBUG
enum HomePreviewData {
    static let now = Date()

    static func row(_ name: String, _ type: String, _ provider: String, _ health: CloudSummary.Health,
                    _ sentence: String, used: Int64?, total: Int64?, finder: Bool = true,
                    tint: Int, last: Date? = nil) -> CloudSummary.Row {
        .init(id: name, providerType: type, providerName: provider, health: health, sentence: sentence,
              quota: used.map { StorageQuota(used: $0, total: total) }, isInFinder: finder,
              tint: tint, lastConnected: last, errorDetail: nil)
    }

    static let tb: Int64 = 1_000_000_000_000
    static let gb: Int64 = 1_000_000_000

    static let personal = row("Personal", "drive", "Google Drive", .ready, "Ready", used: 1_280 * gb, total: 2 * tb, tint: 0)
    static let work = row("Work", "onedrive", "Microsoft OneDrive", .needsSignIn, "Needs sign-in", used: 412 * gb, total: 1 * tb, tint: 1)
    static let workReady = row("Work", "onedrive", "Microsoft OneDrive", .ready, "Ready", used: 412 * gb, total: 1 * tb, tint: 1)
    static let dropbox = row("Dropbox", "dropbox", "Dropbox", .busy, "Uploading 3 items, 2 min left", used: 61 * gb, total: 2 * tb, finder: false, tint: 2)
    static let archive = row("Photo Archive", "b2", "Backblaze B2", .ready, "Ready", used: 720 * gb, total: nil, finder: false, tint: 3)
    static let nas = row("Home NAS", "sftp", "SSH/SFTP", .unreachable, "Can't reach this server right now", used: nil, total: nil, finder: false, tint: 4, last: now.addingTimeInterval(-2 * 86_400))

    static func summary(_ rows: [CloudSummary.Row], overall: CloudSummary.Overall, attention: CloudSummary.Row? = nil,
                        suggestions: [CloudSummary.Suggestion] = []) -> CloudSummary {
        var used: Int64 = 0, capacity: Int64 = 0
        var free: Int64?
        for r in rows { if let q = r.quota {
            used += q.used ?? 0
            if let t = q.total { capacity += t; free = (free ?? 0) + (q.free ?? 0) } else { capacity += q.used ?? 0 }
        } }
        return CloudSummary(rows: rows, overall: overall, attention: attention, suggestions: suggestions,
                            usedBytes: used, freeBytes: free, capacityBytes: capacity)
    }

    static let activity: [ActivityLine] = [
        .init(id: UUID(), text: "Copied Yosemite 2026 to Photo Archive", date: now.addingTimeInterval(-7_200), isFailure: false, cloud: "Photo Archive"),
        .init(id: UUID(), text: "Couldn't copy Client Work to Dropbox", date: now.addingTimeInterval(-90_000), isFailure: true, cloud: "Dropbox"),
    ]
}

#Preview("Needs sign-in", traits: .fixedLayout(width: 1000, height: 760)) {
    let rows = [HomePreviewData.personal, HomePreviewData.work, HomePreviewData.dropbox, HomePreviewData.archive, HomePreviewData.nas]
    HomeContent(
        summary: HomePreviewData.summary(rows, overall: .needsAttention(HomePreviewData.work), attention: HomePreviewData.work,
                                         suggestions: [.notInFinder(HomePreviewData.archive)]),
        activity: HomePreviewData.activity, providerCount: 72)
}

#Preview("All ready", traits: .fixedLayout(width: 1000, height: 620)) {
    let rows = [HomePreviewData.personal, HomePreviewData.workReady, HomePreviewData.archive]
    HomeContent(summary: HomePreviewData.summary(rows, overall: .allReady), activity: [], providerCount: 72)
}

#Preview("Busy, narrow", traits: .fixedLayout(width: 700, height: 760)) {
    let rows = [HomePreviewData.personal, HomePreviewData.dropbox]
    HomeContent(summary: HomePreviewData.summary(rows, overall: .busy(.init(progress: 0.4, sentence: "Copying 3 items to Dropbox"))),
                activity: HomePreviewData.activity, providerCount: 72)
}

#Preview("No clouds", traits: .fixedLayout(width: 900, height: 600)) {
    HomeContent(summary: HomePreviewData.summary([], overall: .noClouds), activity: [], providerCount: 72)
}

#Preview("Engine down", traits: .fixedLayout(width: 900, height: 600)) {
    HomeContent(summary: HomePreviewData.summary([], overall: .engineDown("rclone exited with status 1")), activity: [], providerCount: 72)
}
#endif
