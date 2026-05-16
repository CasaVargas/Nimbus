import AppKit
import SwiftUI
import RcloneKit
import UniformTypeIdentifiers

/// Owns the NSTableView data source + delegate, drag source, key
/// dispatch, and selection bridging. All AppKit complexity for the
/// Browser list is isolated here. Selection math is delegated to the
/// existing Selection<String> via SelectionIntent — this class only
/// interprets NSTableView events.
@MainActor
final class FileTableCoordinator: NSObject {
    // Inputs, refreshed by FileTableRepresentable.updateNSView.
    var files: [FileItem] = [] {
        didSet { rebuildRowIndex() }
    }
    var remote: String = ""
    let selection: Selection<String>
    let keyboard: KeyboardCoordinator
    var onOpen: (FileItem) -> Void
    var onContextAction: (FileItem, FileAction) -> Void
    var onQuickLook: ([FileItem]) -> Void
    var onSortHeaderClick: (SortField) -> Void

    /// SwiftUI environment objects forwarded from FileTableRepresentable so
    /// FileRowHostingCell can inject them into NSHostingView<FileRowView>.
    /// These are set in updateNSView; nil until the first SwiftUI update fires.
    var transferStore: TransferStore?
    var fileProviderBridge: FileProviderBridge?

    weak var tableView: FileTableView?

    /// Files-identity signal for the last list applied via
    /// `FileTableRepresentable.updateNSView`. `FileItem` is not `Equatable`,
    /// so we compare the id ordering (`files.map(\.id)`, id is `String`).
    /// `hasAppliedFiles` forces the first updateNSView to apply+reload even
    /// when both the stored signal and the incoming files are empty (an
    /// initially-empty directory must still reload exactly once).
    private(set) var appliedFileIDs: [String] = []
    private(set) var hasAppliedFiles = false

    /// Apply `newFiles` only when the list actually changed since the last
    /// applied signal (or on the very first call). Returns `true` when the
    /// caller should follow up with `reloadPreservingSelection()`. SwiftUI
    /// re-invokes updateNSView on every BrowserView re-render (e.g. each
    /// TransferStore progress tick during an active transfer over a large
    /// directory); gating here avoids a redundant O(n) rebuildRowIndex
    /// (`files` didSet) + full NSTableView.reloadData() per tick.
    func applyFilesIfChanged(_ newFiles: [FileItem]) -> Bool {
        let signal = newFiles.map(\.id)
        if hasAppliedFiles && signal == appliedFileIDs { return false }
        files = newFiles            // fires didSet → rebuildRowIndex (only when changed)
        appliedFileIDs = signal
        hasAppliedFiles = true
        return true
    }

    /// Guards the SwiftUI→AppKit→SwiftUI selection echo loop.
    private var isApplyingSelection = false

    /// Reverse index id → row, rebuilt on every `files` assignment so
    /// `row(forID:)` is O(1). Without this, syncTableSelectionFromModel
    /// is O(selected × n) and select-all on a 10k dir blows the pillar-4
    /// 200ms budget by ~10×.
    private var rowIndexByID: [String: Int] = [:]

    private func rebuildRowIndex() {
        rowIndexByID = Dictionary(
            files.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }   // FileItem.id should be unique; keep first defensively
        )
    }

    init(
        selection: Selection<String>,
        keyboard: KeyboardCoordinator,
        onOpen: @escaping (FileItem) -> Void,
        onContextAction: @escaping (FileItem, FileAction) -> Void,
        onQuickLook: @escaping ([FileItem]) -> Void,
        onSortHeaderClick: @escaping (SortField) -> Void
    ) {
        self.selection = selection
        self.keyboard = keyboard
        self.onOpen = onOpen
        self.onContextAction = onContextAction
        self.onQuickLook = onQuickLook
        self.onSortHeaderClick = onSortHeaderClick
    }

    private var ordering: [String] { files.map(\.id) }
    private func file(atRow row: Int) -> FileItem? {
        files.indices.contains(row) ? files[row] : nil
    }
    private func row(forID id: String) -> Int? { rowIndexByID[id] }

    /// Push the current Selection.ids into the NSTableView selection.
    /// Called after keyboard-driven / type-to-select changes. NOTE: this
    /// does NOT reload the table — for a reload, Task 6's updateNSView
    /// MUST call `reloadPreservingSelection()` instead of touching the
    /// table directly, otherwise reloadData()'s selection-cleared
    /// notification can wipe the model selection.
    func syncTableSelectionFromModel() {
        guard let tableView else { return }
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        let indexes = IndexSet(selection.ids.compactMap { row(forID: $0) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    /// Reload the table and restore the model selection atomically. Brackets
    /// the whole operation in isApplyingSelection so reloadData()'s internal
    /// selection-cleared notification doesn't wipe the model. Task 6's
    /// updateNSView MUST call this, not tableView.reloadData() directly.
    func reloadPreservingSelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        tableView?.reloadData()
        let indexes = IndexSet(selection.ids.compactMap { row(forID: $0) })
        tableView?.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    /// NSTableView double-click → open the clicked row, mirroring the grid's
    /// `TapGesture(count: 2)` path (FileGrid:67). `clickedRow` is valid for
    /// the duration of a doubleAction dispatch.
    @objc func handleDoubleClick(_ sender: NSTableView) {
        guard let f = file(atRow: sender.clickedRow) else { return }
        onOpen(f)
    }
}

// MARK: - NSTableViewDataSource

extension FileTableCoordinator: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    // Drag source: emit NimbusFileBundle as JSON so the unchanged SwiftUI
    // `.dropDestination(for: NimbusFileBundle.self)` (BrowserView:99) decodes it.
    func tableView(_ tableView: NSTableView,
                    pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard let dragged = file(atRow: row) else { return nil }
        let inSelection = selection.ids.contains(dragged.id)
        let sources: [FileItem] = inSelection
            ? files.filter { selection.ids.contains($0.id) }
            : [dragged]
        let bundle = NimbusFileBundle(refs: sources.map {
            NimbusFileRef(remoteName: remote, path: $0.path,
                          size: $0.size, isDir: $0.isDir)
        })
        guard let data = try? JSONEncoder().encode(bundle) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: .init(UTType.json.identifier))
        return item
    }
}

// MARK: - NSTableViewDelegate

extension FileTableCoordinator: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                    viewFor tableColumn: NSTableColumn?,
                    row: Int) -> NSView? {
        guard let file = file(atRow: row) else { return nil }
        let cell = tableView.makeView(
            withIdentifier: FileRowHostingCell.reuseIdentifier, owner: self
        ) as? FileRowHostingCell ?? FileRowHostingCell()
        cell.identifier = FileRowHostingCell.reuseIdentifier
        cell.transferStore = transferStore
        cell.fileProviderBridge = fileProviderBridge
        cell.configure(file: file, remote: remote,
                       isSelected: selection.ids.contains(file.id))
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        FileRowView.rowHeight
    }

    // Mouse-driven selection: NSTableView already updated selectedRowIndexes
    // by the time this fires. Translate to the model via SelectionIntent so
    // anchor semantics match Finder for mixed mouse+keyboard input.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection, let tableView else { return }
        let clicked = tableView.clickedRow
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if clicked >= 0, let f = file(atRow: clicked) {
            SelectionIntent.forClick(modifiers: modifiers)
                .apply(to: selection, id: f.id, ordering: ordering)
        } else {
            // Programmatic / select-all / drag-select: mirror raw indexes.
            let ids = Set(tableView.selectedRowIndexes.compactMap {
                file(atRow: $0)?.id
            })
            selection.replace(with: ids, in: ordering)
        }
        // Reflect the model back (intent may differ from NSTableView's raw set).
        syncTableSelectionFromModel()
    }

    func tableView(_ tableView: NSTableView,
                   shouldReorderColumn columnIndex: Int,
                   toColumn newColumnIndex: Int) -> Bool { false }
}

// MARK: - FileTableKeyResponding

extension FileTableCoordinator: FileTableKeyResponding {
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)

        // Type-to-select: first non-modified letter/digit/._-
        if modifiers.isEmpty, let c = chars.first,
           c.isLetter || c.isNumber || ".-_".contains(c) {
            keyboard.handleTypeToSelect(char: c, against: files.map(\.name)) { name in
                if let f = files.first(where: { $0.name == name }) {
                    selection.select(f.id, in: ordering)
                    syncTableSelectionFromModel()
                    if let r = row(forID: f.id) {
                        tableView?.scrollRowToVisible(r)
                    }
                }
            }
            return true
        }

        switch event.keyCode {
        case 49: // space → Quick Look
            let items = files.filter { selection.ids.contains($0.id) }
            if !items.isEmpty { onQuickLook(items) }
            return true
        case 36, 76: // return / enter → open anchor
            if let id = selection.anchor, let f = files.first(where: { $0.id == id }) {
                onOpen(f)
            }
            return true
        case 51, 117: // delete / forward-delete → context delete
            if let id = selection.anchor, let f = files.first(where: { $0.id == id }) {
                onContextAction(f, .delete)
            }
            return true
        case 125, 126: // down (125) / up (126) arrows
            moveSelection(down: event.keyCode == 125,
                          extend: modifiers.contains(.shift))
            return true
        default:
            return false
        }
    }

    private func moveSelection(down: Bool, extend: Bool) {
        guard !files.isEmpty else { return }
        let order = ordering
        let currentID = selection.anchor ?? (down ? order.first : order.last)
        let currentIdx = currentID.flatMap { order.firstIndex(of: $0) } ?? 0
        let nextIdx = max(0, min(order.count - 1, currentIdx + (down ? 1 : -1)))
        let targetID = order[nextIdx]
        if extend {
            SelectionIntent.extend.apply(to: selection, id: targetID, ordering: order)
        } else {
            SelectionIntent.select.apply(to: selection, id: targetID, ordering: order)
        }
        syncTableSelectionFromModel()
        tableView?.scrollRowToVisible(nextIdx)
    }

    func contextMenu(forRow row: Int) -> NSMenu? {
        guard let f = file(atRow: row) else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: FileAction) {
            let item = NSMenuItem(
                title: title, action: #selector(contextMenuFired(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ContextPayload(file: f, action: action)
            menu.addItem(item)
        }
        add("Open", .open)
        if f.isDir { add("Add to Bookmarks", .bookmark) }
        if !f.isDir {
            menu.addItem(.separator())
            add("Download Now", .download)
            add("Remove Local Copy", .evict)
        }
        menu.addItem(.separator())
        add("Rename", .rename)
        add("Delete", .delete)
        return menu
    }

    private final class ContextPayload: NSObject {
        let file: FileItem
        let action: FileAction
        init(file: FileItem, action: FileAction) {
            self.file = file; self.action = action
        }
    }

    @objc private func contextMenuFired(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextPayload else { return }
        onContextAction(payload.file, payload.action)
    }
}
