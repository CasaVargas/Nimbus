import SwiftUI
import RcloneKit

/// Navigates a remote's folder tree so the user can pick a copy/sync path
/// instead of typing it. Lists only directories (files are irrelevant for a
/// path target). Selecting at the root returns "" — i.e. the whole remote.
struct FolderBrowserSheet: View {
    let remote: String
    let client: RcloneClient
    /// Called with the chosen rclone-relative path ("" == remote root).
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Path segments from the remote root to the current directory.
    @State private var segments: [String] = []
    @State private var folders: [FileItem] = []
    @State private var isLoading = false
    @State private var error: NimbusError?

    private var currentPath: String { segments.joined(separator: "/") }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .task(id: currentPath) { await load() }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                crumb(title: remote, depth: 0)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, name in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    crumb(title: name, depth: index + 1)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.m)
            .padding(.vertical, DesignSystem.Spacing.s)
        }
    }

    private func crumb(title: String, depth: Int) -> some View {
        Button {
            segments = Array(segments.prefix(depth))
        } label: {
            Text(verbatim: title)
                .font(DesignSystem.Typography.caption)
                .fontWeight(depth == segments.count ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            depth == segments.count
                ? DesignSystem.Color.semantic.textPrimary
                : DesignSystem.Color.semantic.accent
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxWidth: .infinity)
        } else if let error {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't list folder",
                messageVerbatim: error.message,
                action: .init(label: "Retry", perform: { Task { await load() } })
            )
        } else if folders.isEmpty {
            EmptyState(
                icon: "folder",
                title: "No subfolders",
                messageVerbatim: "This folder has no subfolders. You can still select it below.",
                action: nil
            )
        } else {
            List(folders) { folder in
                Button {
                    segments.append(folder.path)
                } label: {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(DesignSystem.Color.semantic.accent)
                        Text(verbatim: folder.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Will select")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                Text(verbatim: "\(remote):\(currentPath)")
                    .font(DesignSystem.Typography.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glassCapsule)
            Button("Select This Folder") {
                onSelect(currentPath)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.primaryPill(.small))
        }
        .padding(DesignSystem.Spacing.m)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let items = try await client.listFiles(fs: "\(remote):", remote: currentPath)
            folders = items
                .filter(\.isDir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}

#Preview {
    FolderBrowserSheet(remote: "gdrive", client: RcloneClient(), onSelect: { _ in })
}
