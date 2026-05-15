# Phase 2d — Browser Performance (AppKit NSTableView Bridge)

**Date:** 2026-05-15
**Status:** Approved
**Type:** Implementation spec
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md` (strategic — Risk + Pillar 4)
- `docs/superpowers/specs/2026-05-15-phase2c-exit-gates.md` (predecessor; NSOutlineView bridge deferred here)

> Inserted between Phase 2c and the strategic doc's Phase 3 (system integration). Addresses the strategic doc's two explicitly-named risks: "Finder-grade file interaction is hard in SwiftUI" and "Performance pillar bites at scale."

## Goal

Replace the SwiftUI `Table` inside `FileTable` with a virtualized AppKit `NSTableView` bridge so 10k-item directories meet pillar 4 (≤200ms cold-load, 120fps scroll) and gain Finder-grade selection semantics (mixed mouse+keyboard shift-extension), **without changing `FileTable`'s public API or `BrowserView`'s call site**.

## Scope

### In scope

1. `FileTableRepresentable: NSViewRepresentable` + `Coordinator` wrapping `NSScrollView`/`NSTableView`.
2. `FileTable` (SwiftUI struct) keeps its exact current signature — `files: [FileItem]`, `remote: String`, `@Bindable selection: Selection<String>`, `@Bindable keyboard: KeyboardCoordinator`, `@Binding sortField: SortField`, `@Binding sortAscending: Bool`, `onOpen`, `onContextAction`, `onQuickLook`. Its `body` renders the representable.
3. Coordinator bridges, all preserving current behavior:
   - `Selection<String>` ↔ `NSTableView.selectedRowIndexes` with a single shared `anchorRow` so shift-extension works across mixed mouse+keyboard.
   - `KeyboardCoordinator` ↔ `keyDown:` (space → Quick Look, return → open, delete → context delete, type-to-select).
   - `.draggable` payload ↔ `NSPasteboardItem` carrying `NimbusFileRef` (cross-remote drag unchanged downstream).
   - Column header click ↔ `sortField` / `sortAscending` bindings.
   - Double-click / Return ↔ `onOpen`. Right-click ↔ `onContextAction` via `NSMenu`. Space ↔ `onQuickLook`.
4. Cells: `FileRowHostingCell: NSTableCellView` hosting a new small SwiftUI `FileRowView` via `NSHostingView`, with a reuse identifier and `prepareForReuse` that cancels the Phase 2c `CloudStatusColumn` async `.task` and clears the hosting rootView.
5. `SelectionReducer` — pure logic seam (`(currentSelection, anchor, event) -> (newSelection, newAnchor)`) that the Coordinator delegates to, so selection semantics are unit-testable without a live `NSTableView`.
6. `FileTablePerfTests` XCTest `measure {}` over the 10k-item data-source `reloadData` + first-window layout path. `BenchScenarios` gains a real data-source sibling to the existing sort-only proxy.

### Out of scope (deferred)

- **`FileGrid` AppKit bridge** — stays SwiftUI `ScrollView`+`LazyVGrid` (adequately virtualized for icon tiles). Revisit only if a future benchmark fails.
- **NSOutlineView / inline folder expansion** — a later "advanced browser modes" phase. The Browser is a flat directory listing; you navigate into folders.
- **Fully automated headless render-FPS harness** — 120fps verified manually via Instruments once, recorded as a ⏳ exit-gate step. A CI FPS harness is its own sub-project.
- **Column resize/reorder persistence across launches** — not a perf blocker. Carry-forward.

### Sequencing

Per-task commits, TDD where the logic is pure (SelectionReducer), build+manual where it's AppKit glue:

1. Extract `FileRowView` from the current Table column closures (no behavior change).
2. `SelectionReducer` pure logic + Swift Testing tests.
3. `FileRowHostingCell` + reuse/teardown.
4. `FileTableView` NSTableView subclass (keyDown / menu overrides).
5. `Coordinator` (data source + delegate + drag + selection via SelectionReducer).
6. `FileTableRepresentable` + rewire `FileTable.body`.
7. `FileTablePerfTests` + `BenchScenarios` real data-source path.
8. Exit verification + exit-gate doc.

## Architecture

### File layout (all under `Nimbus/Nimbus/Views/Browser/`)

```
FileTable.swift                 (MODIFIED — struct keeps exact API; body = FileTableRepresentable(...))
FileRowView.swift               (NEW — SwiftUI row: icon + name + size + modified + CloudStatusColumn)
FileRowHostingCell.swift        (NEW — NSTableCellView hosting FileRowView via NSHostingView)
FileTableView.swift             (NEW — NSTableView subclass: keyDown:, menu(for:) overrides)
FileTableRepresentable.swift    (NEW — NSViewRepresentable: makeNSView/updateNSView/makeCoordinator)
FileTableCoordinator.swift      (NEW — NSObject: data source + delegate + dragging source)
SelectionReducer.swift          (NEW — pure selection logic seam)
```

`BrowserView.swift` is unchanged (the `FileTable(...)` call site at line 38 keeps its arguments).

### `FileRowView` (NEW)

Extracted verbatim from the current `Table`'s per-column closures: leading `CloudStatusColumn(file:remote:)` async badge, folder/file icon, name (`Typography.body`, `lineLimit(1)`), size, modified date. All DesignSystem tokens preserved. This is the single source of truth for row appearance, hosted inside the AppKit cell. Fixed height from a DesignSystem token (no self-sizing — avoids `NSHostingView`-in-`NSTableView` autolayout thrash).

### `SelectionReducer` (NEW — the testable core)

```swift
struct SelectionReducer {
    enum Event {
        case plainClick(id: String)
        case commandClick(id: String)
        case shiftClick(id: String)
        case keyboardExtend(toID: String)   // shift-arrow
        case keyboardMove(toID: String)     // plain arrow
        case refresh(survivingIDsInOrder: [String])
    }
    struct State: Equatable {
        var selected: Set<String>
        var anchor: String?
    }
    /// Pure: given current state, the ordered visible ids, and an event,
    /// returns the next state. No NSTableView, no SwiftUI.
    static func reduce(_ state: State, ids: [String], event: Event) -> State
}
```

Rules: plain click → `selected = {id}`, `anchor = id`. ⌘-click → toggle id in `selected`, `anchor` unchanged. shift-click / keyboard-extend → `selected = closed range between anchor and target in ids order`, `anchor` unchanged. plain keyboard-move → like plain click. refresh → `selected = selected ∩ surviving`, `anchor = anchor if surviving else nearest survivor in prior order else nil`.

### `Coordinator`

`final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSPasteboardItemDataProvider`. Holds the sorted `files` snapshot, a `SelectionReducer.State`, a back-reference to `Selection<String>` / `KeyboardCoordinator` / the closures, and an `isApplyingSelection` reentrancy guard. Translates `NSTableView` selection deltas into `SelectionReducer.Event`s, applies the reduced state to both `NSTableView` and `Selection<String>` (guard prevents echo loop). `pasteboardWriter(forRow:)` emits `NimbusFileRef`. Column header click flips the sort bindings.

### `FileTableView` (NSTableView subclass)

Overrides `keyDown(with:)` → forwards to the Coordinator which routes to `KeyboardCoordinator`. Overrides `menu(for:)` → builds an `NSMenu` from `onContextAction` for the row under the event.

### `FileTableRepresentable`

`makeNSView` builds `NSScrollView` → `FileTableView` with columns matching today's (status / Name / Size / Modified). `updateNSView` stores the new sorted `files` on the Coordinator and decides `reloadData()` vs. animated row diff by `FileItem.id`. `makeCoordinator` returns the `Coordinator`.

### Concurrency

All AppKit types are main-actor by construction. `Selection` / `KeyboardCoordinator` are already `@Observable @MainActor`. The only async surface is the per-cell `CloudStatusColumn .task` (from Phase 2c) — unchanged except for explicit cancellation on `prepareForReuse`.

## Data flow

### Cold load (≤200ms path)
`BrowserViewModel.loadFiles()` (unchanged: fetch + sort + cache) → `files` published → `FileTable.body` → `FileTableRepresentable.updateNSView` → `coordinator.files = sorted` → `reloadData()` → `NSTableView` instantiates only visible-window cells (~30-50) → each dequeues a `FileRowHostingCell` → `NSHostingView(rootView: FileRowView(...))` → that row's `CloudStatusColumn .task` fires. Cost dominated by VM sort (already measured Phase 1) + `reloadData`, not cell count.

### Scroll (120fps path)
`NSTableView` recycles cells: `prepareForReuse` cancels the old row's `CloudStatusColumn` task + clears rootView; reconfigure sets the new `FileRowView` rootView; new `.task(id: "\(remote)|\(file.path)")` fires. Constant live-cell count → frame rate independent of directory size.

### Selection (mixed input)
Mouse and keyboard events both become `SelectionReducer.Event`s applied against one shared `State.anchor`. Mixed mouse+keyboard shift-extension works because the anchor is single-sourced — the Phase 1/2a gap the in-code NOTE flagged.

### Drag / actions
Drag → `pasteboardWriter` → `NimbusFileRef` → existing `DragDropCoordinator` consumes unchanged. Double-click/Return → `onOpen`. Right-click → `NSMenu` from `onContextAction`. Space → `onQuickLook`. Column header → sort bindings → VM re-sort → `updateNSView`.

No changes to `BrowserViewModel`, `Selection`, `KeyboardCoordinator`, `DragDropCoordinator`, `CloudStatusColumn`, or `BrowserView`.

## Error handling & edge cases

| Edge case | Handling |
|-----------|----------|
| Empty directory | `numberOfRows == 0`; `BrowserView` already shows `EmptyState` above the table. No special case. |
| `files` mutates mid-scroll | `updateNSView` diffs by `FileItem.id`: metadata-only → reload affected rows; structural → `reloadData`. |
| Selected file disappears after refresh | `SelectionReducer.reduce(_, _, .refresh(...))` intersects ids; anchor falls back to nearest survivor or nil. |
| Cell reuse races async badge | `prepareForReuse` cancels `CloudStatusColumn .task` + clears rootView before reconfigure; new `.task(id:)` keyed on `"\(remote)|\(file.path)"`. |
| SwiftUI↔AppKit selection echo loop | `isApplyingSelection` reentrancy guard in the Coordinator. |
| Sort header click during in-flight fetch | Sort bindings update → VM re-sorts current `files`; late fetch result sorted by current bindings. Existing VM behavior. |
| `NSHostingView` row-height autolayout thrash | Fixed `tableView.rowHeight` from DesignSystem token; `FileRowView` constrained to it. No self-sizing rows. |
| Type-to-select no match | `KeyboardCoordinator` already no-ops; Coordinator just forwards `keyDown:`. |
| VoiceOver | `NSTableView` natively accessible; `FileRowView` `.accessibilityLabel`s carry through `NSHostingView`. Manual ⏳ verify. |

No new `NimbusError` surface. AppKit-internal failures degrade to "reload the table," never user-facing.

## Testing

| Suite | Framework | Tests | Verifies |
|-------|-----------|-------|----------|
| `FileTablePerfTests` | XCTest (`measure {}`) | 1 | 10k synthetic `FileItem`s → Coordinator data source → `reloadData` + first-window layout ≤200ms baseline. |
| `SelectionReducerTests` | Swift Testing | ~6 | plain-click anchor+single; ⌘-click toggle preserves anchor; shift-click range from anchor; shift-extend after ⌘-click; refresh drops missing ids; anchor resets when its id disappears. |

`BenchScenarios` keeps the existing sort-only `load10kItems()` (still measures VM sort budget) and adds a sibling exercising the real data-source `reloadData` path, called from `FileTablePerfTests`.

XCTest and Swift Testing coexist in the existing test target (already true in this project).

### Manual / ⏳ exit-gate steps

- Instruments Time Profiler + Core Animation FPS on a real 10k-item directory → confirm 120fps, no dropped frames; record trace summary.
- Mixed mouse+keyboard selection walkthrough: click → shift-↓ → ⌘-click → shift-click; Finder-identical.
- Cross-remote drag enqueues a Copy transfer.
- Quick Look (space), context menu (right-click), double-click open, type-to-select.
- VoiceOver row navigation.
- Side-by-side vs Finder list view (pillar subjective gate).

Test count: 105 baseline + 1 XCTest perf + ~6 SelectionReducer ≈ **112**.

## Implementation order

1. `FileRowView` extraction (no behavior change) — ~0.5d
2. `SelectionReducer` + ~6 Swift Testing tests — ~1d
3. `FileRowHostingCell` + reuse/teardown — ~0.5d
4. `FileTableView` subclass (keyDown/menu) — ~0.5d
5. `FileTableCoordinator` (data source + delegate + drag + SelectionReducer wiring) — ~1.5d
6. `FileTableRepresentable` + rewire `FileTable.body` — ~1d
7. `FileTablePerfTests` + `BenchScenarios` real path — ~0.5d
8. Exit verification + exit-gate doc — ~0.5d

≈ 6 days serial. Test count 105 → ~112.

## Phase 2d exit gates

| Gate | Target |
|------|--------|
| All baseline tests still green | 105 → 105 |
| New tests pass | +~7 |
| `FileTable` public API unchanged | `BrowserView` diff zero/trivial |
| 10k data-source `reloadData` + first-window layout | ≤200ms (XCTest measure) |
| 120fps scroll on 10k dir | ⏳ Instruments, recorded in exit-gate doc |
| Mixed mouse+keyboard shift-extension | ✅ works (the flagged gap) |
| Cross-remote drag / Quick Look / context menu / dbl-click / type-to-select | all preserved |
| VoiceOver row navigation | ⏳ user-verified |
| Lints green; `Package.resolved` unchanged | ✅ |

## What's next

Phase 2d → strategic-doc Phase 3 (system integration depth — Quick Look provider, Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish, notifications).

Carry-forwards still open after 2d: `wasRecentlyEvicted` SDK gap (Phase 3), `RcloneSection` Version + Restart rows (RcloneDaemon API), OAuth re-auth on Reconnect (Phase 4), column resize/reorder persistence, `FileGrid` AppKit bridge (only if a future benchmark fails), inherited Phase 2a/1 carry-forwards (ConfigForm name-row dup, LocalizedStringKey runtime strings, NimbusUITests target).
