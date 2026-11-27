import RcloneKit
import SwiftUI

/// File browser gallery view: one large preview of the selected item over
/// a filmstrip of the folder. Photos and PDFs draw as pictures (the same
/// rule Finder thumbnails follow); everything else keeps its icon.
struct FileGallery: View {
    enum Layout {
        static let cellSize: CGFloat = 72
        static let cellSpacing: CGFloat = DesignSystem.Spacing.s
        static let stripHeight: CGFloat = cellSize + 2 * DesignSystem.Spacing.m
        static let previewIconSize: CGFloat = 128
        /// Pixels on the long side. Filmstrip cells are drawn at 2x.
        static let cellMaxPixel = Int(cellSize) * 2
        static let previewMaxPixel = 1600
    }

    let files: [FileItem]
    let remote: String
    @Bindable var selection: Selection<String>
    let thumbnails: (any GalleryThumbnailProviding)?
    let onOpen: (FileItem) -> Void
    let onContextAction: (FileItem, FileAction) -> Void
    let onQuickLook: ([FileItem]) -> Void
    var allowsModifying = true

    @FocusState private var hasFocus: Bool

    private var ids: [String] { files.map(\.id) }

    private var currentID: String? {
        GallerySelection.current(selected: selection.ids, in: ids)
    }

    private var currentFile: FileItem? {
        currentID.flatMap { id in files.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            filmstrip
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
        .onKeyPress(.return) { act { onOpen($0) } }
        .onKeyPress(.space) { act { onQuickLook([$0]) } }
        .onAppear {
            hasFocus = true
            repairSelection()
        }
        .onChange(of: ids) { repairSelection() }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let file = currentFile {
            VStack(spacing: DesignSystem.Spacing.m) {
                GalleryThumbnail(
                    file: file, remote: remote, thumbnails: thumbnails,
                    maxPixel: Layout.previewMaxPixel, iconSize: Layout.previewIconSize,
                    // The filmstrip's picture stands in while the large one loads.
                    standInMaxPixel: Layout.cellMaxPixel, fills: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 2).onEnded { onOpen(file) })
                .contextMenu {
                    FileContextMenu(file: file, onAction: { onContextAction(file, $0) }, allowsModifying: allowsModifying)
                }
                .accessibilityLabel(file.name)

                caption(for: file)
            }
            .padding(DesignSystem.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func caption(for file: FileItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(file.name)
                .font(DesignSystem.Typography.bodyEmphasized)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Self.detail(for: file))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        }
    }

    /// "3.1 MB · 12 Nov 2026"; folders and unknown sizes leave the part out.
    static func detail(for file: FileItem) -> String {
        var parts: [String] = []
        if file.isDir {
            parts.append("Folder")
        } else if file.size >= 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
        }
        if let date = file.modTime {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Layout.cellSpacing) {
                    ForEach(files) { file in
                        cell(for: file)
                            .id(file.id)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.l)
                .padding(.vertical, DesignSystem.Spacing.m)
            }
            .frame(height: Layout.stripHeight)
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation(DesignSystem.Motion.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func cell(for file: FileItem) -> some View {
        let isSelected = file.id == currentID
        return GalleryThumbnail(
            file: file, remote: remote, thumbnails: thumbnails,
            maxPixel: Layout.cellMaxPixel, iconSize: Layout.cellSize * 0.6, standInMaxPixel: nil,
            fills: true
        )
        .frame(width: Layout.cellSize, height: Layout.cellSize)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
                .strokeBorder(isSelected ? DesignSystem.Color.semantic.selection : .clear, lineWidth: 3)
        }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { onOpen(file) })
        .simultaneousGesture(TapGesture().onEnded {
            hasFocus = true
            selection.select(file.id, in: ids)
        })
        .draggable(NimbusFileBundle(refs: [
            NimbusFileRef(remoteName: remote, path: file.path, size: file.size, isDir: file.isDir),
        ]))
        .contextMenu {
            FileContextMenu(file: file, onAction: { onContextAction(file, $0) }, allowsModifying: allowsModifying)
        }
        .help(file.name)
        .accessibilityLabel(file.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Selection

    /// Gallery shows exactly one item: collapse an empty, stale or multiple
    /// selection onto it.
    private func repairSelection() {
        guard let id = currentID, selection.ids != [id] else { return }
        selection.select(id, in: ids)
    }

    private func step(by delta: Int) -> KeyPress.Result {
        guard let next = GallerySelection.step(from: currentID, by: delta, in: ids) else { return .ignored }
        selection.select(next, in: ids)
        return .handled
    }

    private func act(_ action: (FileItem) -> Void) -> KeyPress.Result {
        guard let file = currentFile else { return .ignored }
        action(file)
        return .handled
    }
}

/// One file drawn as its picture when it has one, as its icon otherwise.
private struct GalleryThumbnail: View {
    let file: FileItem
    let remote: String
    let thumbnails: (any GalleryThumbnailProviding)?
    let maxPixel: Int
    let iconSize: CGFloat
    let standInMaxPixel: Int?
    /// Crop to fill the frame (filmstrip cells) instead of fitting inside it.
    let fills: Bool

    @State private var loaded: CGImage?

    private var request: ThumbnailRequest {
        ThumbnailRequest(file: file, remote: remote, maxPixel: maxPixel)
    }

    /// What can be drawn right now without waiting.
    private var immediate: CGImage? {
        guard let thumbnails, request.kind != nil else { return nil }
        if let hit = thumbnails.cachedImage(for: request) { return hit }
        return standInMaxPixel.flatMap {
            thumbnails.cachedImage(for: ThumbnailRequest(file: file, remote: remote, maxPixel: $0))
        }
    }

    var body: some View {
        Group {
            if let image = loaded ?? immediate {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
            } else {
                Image(nsImage: FileIcon.image(for: file))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keyed on the request: a new selection or an edited file starts
        // over, and a cell that scrolls away cancels its turn.
        .task(id: request) {
            loaded = nil
            guard let thumbnails, request.kind != nil else { return }
            let image = await thumbnails.image(for: request)
            if !Task.isCancelled { loaded = image }
        }
    }
}
