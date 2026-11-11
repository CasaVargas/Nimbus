import SwiftUI
import AppKit
import RcloneKit

/// Detail pane while the toolbar search field has text: one section per
/// cloud, each filling in as its search finishes.
struct SearchResultsView: View {
    let query: String
    let remotes: [Remote]
    /// Opens a cloud's Files tab at a folder path.
    let onShowInNimbus: (_ remote: String, _ folder: String) -> Void

    @Environment(RcloneDaemon.self) private var daemon
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderBridge.self) private var fileProviderBridge
    @State private var model: SearchViewModel?

    var body: some View {
        Group {
            if !SearchViewModel.isSearchable(query) {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "Search every cloud",
                    message: "Type at least two letters to search file and folder names.",
                    action: nil
                )
            } else if let model {
                results(model)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Search")
        .task(id: SearchViewModel.normalized(query)) {
            let model = model ?? SearchViewModel(client: daemon.client)
            self.model = model
            guard SearchViewModel.isSearchable(query) else {
                model.clear()
                return
            }
            do {
                try await Task.sleep(for: SearchViewModel.debounce)
            } catch {
                return
            }
            await model.search(query, in: remotes)
        }
    }

    @ViewBuilder
    private func results(_ model: SearchViewModel) -> some View {
        if model.clouds.isEmpty && model.query.isEmpty {
            // Debouncing the first query.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.clouds.isEmpty {
            EmptyState(icon: "icloud.slash", title: "No clouds to search", message: "Add a cloud first.", action: nil)
        } else {
            List {
                ForEach(model.clouds) { cloud in
                    Section {
                        ForEach(cloud.items, id: \.qualifiedRemotePath) { file in
                            SearchResultRow(file: file)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { showInNimbus(file, remote: cloud.remote) }
                                .contextMenu { menu(for: file, remote: cloud.remote) }
                        }
                    } header: {
                        SearchSectionHeader(cloud: cloud)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func menu(for file: FileItem, remote: String) -> some View {
        Button("Show in Nimbus") { showInNimbus(file, remote: remote) }
        if FinderIntegration.isShown(remote: remote, settings: settings) {
            Button("Show in Finder") { Task { await revealInFinder(file, remote: remote) } }
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(remote):\(file.path)", forType: .string)
        }
    }

    /// A folder opens itself; a file opens the folder that holds it.
    private func showInNimbus(_ file: FileItem, remote: String) {
        onShowInNimbus(remote, file.isDir ? file.path : SearchResultRow.parentPath(of: file.path))
    }

    private func revealInFinder(_ file: FileItem, remote: String) async {
        guard let url = await fileProviderBridge.urlForItem(remote: remote, path: file.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct SearchSectionHeader: View {
    let cloud: CloudSearchResult

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            ProviderBadge(provider: cloud.providerType, size: 18)
            Text(verbatim: cloud.remote)
                .font(DesignSystem.Typography.headline)
            Spacer()
            status
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    @ViewBuilder
    private var status: some View {
        switch cloud.phase {
        case .searching:
            HStack(spacing: DesignSystem.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Searching…")
            }
        case .done where cloud.total == 0:
            Text("No matches")
        case .done where cloud.isTruncated:
            Text("Showing \(cloud.items.count) of \(cloud.total)")
        case .done:
            Text(cloud.total == 1 ? "1 result" : "\(cloud.total) results")
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
                .lineLimit(1)
        case .timedOut:
            Label("Took too long. Narrow the search or browse instead.", systemImage: "clock.badge.exclamationmark")
                .lineLimit(1)
        }
    }
}

struct SearchResultRow: View {
    let file: FileItem

    static func parentPath(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(nsImage: FileIcon.image(for: file))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: file.name)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                folder
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: DesignSystem.Spacing.m)
            if !file.isDir {
                Text(file.size, format: .byteCount(style: .file))
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .frame(width: 80, alignment: .trailing)
            }
            Group {
                if let date = file.modTime {
                    Text(date, style: .date)
                } else {
                    Text(verbatim: "--")
                }
            }
            .font(DesignSystem.Typography.callout)
            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var folder: some View {
        let parent = Self.parentPath(of: file.path)
        if parent.isEmpty {
            Text("Top level")
        } else {
            Text(verbatim: parent)
        }
    }
}

#Preview("Search results") {
    let file = { (path: String, dir: Bool) in
        FileItem(path: path, name: (path as NSString).lastPathComponent, size: dir ? 0 : 248_000,
                 mimeType: "", modTime: .now, isDir: dir, fileID: nil, qualifiedRemotePath: path)
    }
    let clouds = [
        CloudSearchResult(remote: "gdrive", providerType: "drive", phase: .done,
                          items: [file("Work/2026/Q3 report.pdf", false), file("Reports", true)], total: 2),
        CloudSearchResult(remote: "dropbox", providerType: "dropbox", phase: .searching),
        CloudSearchResult(remote: "s3-archive", providerType: "s3", phase: .timedOut),
        CloudSearchResult(remote: "onedrive", providerType: "onedrive", phase: .failed("Sign in again to search this cloud.")),
    ]
    return List {
        ForEach(clouds) { cloud in
            Section {
                ForEach(cloud.items, id: \.qualifiedRemotePath) { SearchResultRow(file: $0) }
            } header: {
                SearchSectionHeader(cloud: cloud)
            }
        }
    }
    .frame(width: 720, height: 420)
}
