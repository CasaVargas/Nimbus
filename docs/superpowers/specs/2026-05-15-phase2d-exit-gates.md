# Phase 2d Exit Gates — Verification

**Date:** 2026-05-15
**Branch:** `phase2d-browser-perf`
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`
- `docs/superpowers/specs/2026-05-15-phase2d-browser-perf-design.md`

**Parent plan:** `docs/superpowers/plans/2026-05-15-phase2d-browser-perf.md`

Records the state of Phase 2d's exit gates at the time of merge readiness. Per the strategic doc, the Browser screen must meet pillar 4 (Performance is a feature) — virtualized rows, Finder-accurate selection, and O(1) data-source operations — before Phase 2d ships.

## Objective gates

| Gate | Target | Status | Evidence |
|------|--------|--------|----------|
| `FileTable` public API unchanged; `BrowserView` call-site byte-unchanged | Zero diff in `BrowserView.swift` across the entire branch | ✅ | `git diff main..HEAD --stat -- Nimbus/Nimbus/Nimbus/Views/Browser/BrowserView.swift` produced no output — byte-for-byte unchanged |
| `FileRowView` extracted, single row-appearance source | Row rendering moved out of `FileTable` columns into a standalone `FileRowView.swift` | ✅ | Task 1 (`ba99c66`): `FileRowView.swift` (97 lines) is the sole source of file-row appearance; `FileTable.swift` gutted of inline column content |
| `SelectionIntent` enum + 7 tests; `Selection.extend` made Finder-accurate (base∪range) + 1 streak test; 1 pre-existing test renamed | See DELIBERATE DEVIATION note below | ✅ | Task 2 (`94c28c0`, `2d456e6`): `SelectionIntent.swift` (29 lines, 3 cases `select`/`toggle`/`extend` + `forClick` + `apply`); 7 tests in `SelectionIntentTests`; `Selection.extend` now snapshots `baseIDs` and unions with live range; `consecutiveExtendStreakKeepsBaseFrozenAndShrinksRange` pins the streak invariant |
| NSTableView bridge live | `FileRowHostingCell` + `FileTableView` + `FileTableCoordinator` + `FileTableRepresentable` all implemented | ✅ | Tasks 3–6 (`8aff170`, `e168e02`, `445148d`, `cdc2ffa`, `f83eb2a`): full NSTableView/NSViewRepresentable bridge in production |
| Environment-bridge fix | `@Environment` objects threaded through the Representable → Coordinator → cell boundary | ✅ | Task 7 (`effaae1`, `15b3a19`): see DELIBERATE IN-SCOPE FIX note below |
| 10k data-source `reloadData` perf | `BenchScenarios.reload10kIntoDataSource` ≤ 200ms | ✅ | `measure {}` average: **9ms** (values: 25, 7.8, 7.3, 7.5, 7.6, 7.3, 7.5, 7.2, 7.1, 7.6 ms). Well under 200ms budget. See PERF CAVEAT below. |
| Full test suite green | 113 Swift Testing tests + 1 XCTest perf test = 114 total methods, 0 failures | ✅ | `Test run with 113 tests in 21 suites passed`; `FileTablePerfTests` suite: `Executed 1 test, with 0 failures` |
| Build-time lints green | `lint-no-system-size: OK`, `lint-package-resolved: OK` | ✅ | Both lint hooks output OK on clean build |
| `Package.resolved` unchanged | No new SPM dependencies | ✅ | No `Package.resolved` file exists; no remote SPM deps added in Phase 2d |
| 120fps scroll on real 10k directory | Instruments Time Profiler + Core Animation FPS | ⏳ User to verify | Windowless XCTest cannot measure per-cell NSHostingView render cost. See PERF CAVEAT below. Manual Instruments gate deferred to user. |
| Cross-remote drag JSON round-trip | Static encode/decode verified; live AppKit-drag → SwiftUI `.dropDestination` smoke | ⏳ User to verify | `NimbusFileBundle` encode/decode is wired in `FileTableCoordinator`; live drag session to a SwiftUI drop target requires user walkthrough |
| Mixed mouse + keyboard shift-extension | Headline interaction Phase 2d fixes: ⌘-click islands + ⇧-click extending from toggled anchor | ⏳ User to verify | `SelectionIntent.forClick` + `Selection.extend` (base∪range) are correct per unit tests; live event routing in `FileTableCoordinator.tableView(_:shouldSelectRow:)` requires user walkthrough |
| Quick Look / context menu / double-click open / type-to-select / arrow+⇧-arrow nav / VoiceOver row nav | Keyboard and accessibility interaction matrix | ⏳ User to verify | All wired in `FileTableCoordinator` key-handler and `FileTableView` overrides; full walkthrough deferred to user |

### DELIBERATE DEVIATION — `Selection.extend` Finder accuracy

The Phase 2d plan asserted that `Selection.extend` already matched Finder's behaviour (pure-replace of the previous range). That assertion was incorrect. The pre-2d implementation did a pure replace: every `extend` call replaced `ids` with just the anchor-to-target range, silently discarding any disjoint items added by prior ⌘-clicks. This means if a user ⌘-clicked items A and C, then ⇧-clicked D, the A selection vanished — non-Finder behaviour.

The fix: `Selection` now snapshots `baseIDs` whenever `select`, `toggle`, `replace`, or `clear` commits a new anchor. Each `extend` call computes `baseIDs ∪ anchor…target range`. Consecutive extend calls reuse the frozen `baseIDs` so the range can shrink without accumulating prior ranges (Finder's pinned-base semantics).

This required renaming one pre-existing test: `extendToAnchorCollapsesToSingle` (which tested and asserted the wrong pure-replace behaviour) is now `extendToAnchorPreservesDisjointSelection` (which asserts the correct base∪range result). This is a deliberate, controller-signed-off deviation — the old test was asserting a bug. One new test `consecutiveExtendStreakKeepsBaseFrozenAndShrinksRange` pins the streak invariant.

### DELIBERATE IN-SCOPE FIX — Environment-bridge across NSHostingView boundary

Discovered during Task 7 (perf) implementation: `CloudStatusColumn` reads `@Environment(TransferStore.self)` and `@Environment(FileProviderBridge.self)`. SwiftUI `@Environment` does **not** cross the imperative `NSHostingView` boundary inside `NSTableView`. Every shipping Browser row would have TRAPPED on first render — `@Environment` of an `@Observable` with no injected value is a fatal precondition violation in Swift.

Fix: both objects are threaded explicitly through the bridge: `FileTableRepresentable` (reads them from SwiftUI `@Environment`) → `FileTableCoordinator` (holds them as stored properties) → `FileRowHostingCell` (receives them as `init` arguments) → `FileRowHost` (a concrete `struct` wrapping `FileRowView` with `.environment(_:)` applied twice). No `AnyView` is used at any point (Task 8 / `15b3a19` replaced an intermediate `AnyView` with the concrete `FileRowHost` wrapper). Production objects (`TransferStore`, `FileProviderBridge`) are confirmed injected at `NimbusApp` root via `.environment(_:)`.

### PERF CAVEAT — what the XCTest measures and what it does not

`BenchScenarios.reload10kIntoDataSource` exercises the O(n) data-prep path: populating a 10k-item `[NimbusFile]` array + `rebuildRowIndex` (O(n) dictionary build, O(1) subsequent `rowIndex[id]` lookups). Average measured: **9ms** (well under the 200ms gate).

What the test does **not** measure: per-cell `NSHostingView` layout, SwiftUI `FileRowView` body evaluation, and GPU compositing — a windowless XCTest has no visible window, so AppKit never lays out cells. The 120fps scroll claim (pillar 4) requires running Nimbus against a real 10k-item rclone remote, opening the Browser, and profiling with Instruments Time Profiler + Core Animation FPS. This is a manual ⏳ gate deferred to the user (recorded above).

## Subjective gates

| Gate | Status | Notes |
|------|--------|-------|
| Browser ↔ Finder list view side-by-side | ⏳ User to verify | AppKit `NSTableView` virtualization replaces the previous SwiftUI `Table`/`List`. Row recycling means only visible rows are live in the view hierarchy — matching Finder's own NSOutlineView virtualization. Fixed-height rows (48pt) allow the data source to skip layout estimation entirely. |
| North-Star pillar 1 — Native or nothing | ⏳ User to verify | `NSTableView` + `NSHostingView` per cell is Apple's own hybrid pattern (demonstrated in WWDC sessions). No third-party virtualization library. `NimbusFileBundle` drag payload uses `NSItemProvider` + `NSPasteboard`. |
| North-Star pillar 2 — Finder-grade interaction | ⏳ User to verify | `Selection.extend` now implements real anchor-pinning (base∪range) matching Finder's ⇧-click semantics. `SelectionIntent.forClick` decodes ⌘/⇧ modifiers into typed intents. Arrow-key navigation and type-to-select are wired in `FileTableCoordinator`. |
| North-Star pillar 3 — Utility-app rigor | ⏳ User to verify | `SelectionIntent` (29 lines, 7 tests), `Selection.extend` (Finder model, 12 tests), `FileRowHostingCell` (reuse teardown cancels CloudStatusColumn task on prepareForReuse) — each is a focused single-responsibility primitive. `FileTableCoordinator` is the one place where data source, delegate, drag, and key handling live. |
| North-Star pillar 4 — Performance is a feature | ⏳ User to verify | Data-source reload: 9ms average for 10k items (automated). Per-cell render + 120fps scroll: manual Instruments gate (see PERF CAVEAT). `FileRowHostingCell.prepareForReuse` cancels in-flight CloudStatus tasks before row recycling to prevent ghost updates. |

## Wedge / Manual smoke

Phase 2d's user-visible wedge is the interaction correctness and scroll feel of the Browser with a large remote:

1. Open a remote with 1000+ items in the Browser. Scroll continuously — it should feel smooth and snappy, with no visible stuttering on fast swipes.
2. Click an item, then ⌘-click two non-adjacent items (disjoint selection). Now ⇧-click another item. The disjoint selection should be **preserved** (base∪range), not collapsed.
3. Click an item, then ⇧-click to extend a range. ⇧-click closer to the anchor — the range should **shrink**, not accumulate the previous tail.
4. Drag a selection across remotes and verify the NimbusFileBundle drop payload reaches the SwiftUI `.dropDestination` handler correctly.
5. Press space on a selected item — Quick Look should open. Right-click — context menu should appear. Double-click — item should open.

**Status:** ⏳ Manual verification pending — user runs once before merge.

## Component status

- ✅ `FileRowView` — single row-appearance source; extracted from `FileTable` columns; used by `FileRowHost` wrapper
- ✅ `SelectionIntent` — 3-case enum (`select`, `toggle`, `extend`); `forClick(modifiers:)` decodes NSEvent modifier flags; `apply(to:id:ordering:)` dispatches to `Selection`; 7 tests. (There is no `.replace` case — `FileTableCoordinator` additionally calls `Selection.replace(with:in:)` directly in its `tableViewSelectionDidChange` else-branch for raw-index mirroring of select-all/drag-select; that is a `Selection` method, not a `SelectionIntent` case.)
- ✅ `Selection` (Finder model) — `baseIDs` snapshot on anchor-commit; `extend` computes `baseIDs ∪ anchor…target`; streak shrinks correctly; 12 tests (11 prior + 1 new streak + 1 renamed)
- ✅ `FileRowHostingCell` — `NSHostingView`-backed table cell; `prepareForReuse` cancels CloudStatusColumn task and resets host; environment objects injected at init
- ✅ `FileTableView` — `NSTableView` subclass; disables automatic cell reuse for explicit `prepareForReuse` control; exposes key-down and right-click hooks
- ✅ `FileTableCoordinator` — data source + delegate + drag source/destination + key handler in one coordinator; O(1) `rowIndex` dictionary rebuilt on each `reloadData`; selection correctness fixed
- ✅ `FileTableRepresentable` — `NSViewRepresentable` bridge; threads `TransferStore`/`FileProviderBridge` from SwiftUI `@Environment` into coordinator. `updateNSView` skips the redundant `coord.files` reassignment + `reloadPreservingSelection()` when the file list is unchanged, via a files-identity guard (`FileTableCoordinator.applyFilesIfChanged` comparing `files.map(\.id)`); cheap inputs (remote/closures/env) still update every call. Prevents a full 10k `reloadData` per TransferStore progress tick during an active transfer over a large directory.
- ✅ `BenchScenarios.reload10kIntoDataSource` — generates 10k `FileItem` items, assigns them directly via `coord.files = items` (firing the `rebuildRowIndex` `didSet`), then calls `table.reloadData()` on a windowless `FileTableView`; used by perf test (there is no `FileTableCoordinator.reload(items:)` method — the bench drives the data source directly)
- ✅ `FileTablePerfTests` — XCTest `measure {}` gates the 200ms O(n) data-source budget; average 9ms observed

## Test suite snapshot

`xcodebuild test -scheme Nimbus -destination 'platform=macOS'`:

> Test run with 113 tests in 21 suites passed.
> FileTablePerfTests suite: Executed 1 test, with 0 failures. (XCTest, separate runner)
> **Total: 114 test methods, 0 failures.**

Note: The Swift Testing harness reports 113 in its summary because `FileTablePerfTests` uses XCTest `measure {}` (not `@Test`) and runs under the legacy XCTest runner. Both runners pass.

| Suite | Tests | Phase |
|-------|-------|-------|
| **SelectionIntent** | **7** | **✅ Phase 2d (Task 2)** |
| **Selection** | **12** | **Phase 1 baseline (11) + Phase 2d +1 streak test; 1 test renamed** |
| **FileTablePerfTests** | **1** | **✅ Phase 2d (Task 7, XCTest measure)** |
| RemoteStatusService | 11 | Phase 2c (Task 4) |
| reconcileFPDomains | 4 | Phase 2c (Task 6) |
| TimedCache | 3 | Phase 2c (Task 8) |
| OnboardingCard | 5 | Phase 2b (Task 2 + fix-up) |
| NimbusError | 5 | Phase 2a (Task 1) |
| SheetChrome | 2 | Phase 2a (Task 2) |
| FormSection | 2 | Phase 2a (Task 2) |
| RemoteRow | 3 | Phase 2a (Task 3) |
| StatusToggle | 4 | Phase 2a (Task 7) |
| MountRow | 4 | Phase 2a (Task 8) |
| ProgressMeter | 4 | Phase 2a (Task 10) |
| TransferRow | 3 | Phase 2a (Task 12) |
| Design system tokens | 4 | Phase 1 baseline |
| EmptyState | 2 | Phase 1 baseline |
| StatusBadge | 8 | Phase 1 baseline |
| KeyboardCoordinator | 9 | Phase 1 baseline |
| DragDropCoordinator | 10 | Phase 1 baseline |
| QuickLookHost MaterializationProvider selection and cleanup | 6 | Phase 1 baseline |
| Accessibility audit | 5 | Phase 1 baseline |
| **Total** | **114** | **Phase 1 (55) + Phase 2a (+27) + Phase 2b (+5) + Phase 2c (+18) + Phase 2d (+9)** |

## Known carry-forwards into next phases

### Phase 2d carry-forwards

1. **Ascending/descending sort has no UI entry point.** PRE-EXISTING — not a Phase 2d regression. The old SwiftUI `Table` headers were never sortable either (plain `TableColumn`, no `sortOrder`); sorting was always toolbar-`sortField`-only with no asc/desc toggle. `FileTableCoordinator.onSortHeaderClick` is forward-plumbing wired but never invoked. Phase 3+: add an asc/desc toggle to `BrowserToolbar` or wire `tableView(_:didClick:)` to cycle `SortField` + direction.

2. **`FileGrid` still uses SwiftUI `LazyVGrid`.** Grid mode was not in Phase 2d scope. Deferred unless a future bench fails for the grid path.

3. **NSOutlineView / inline folder expansion.** Advanced browser modes phase — not Phase 2d.

4. **Column resize/reorder persistence.** `NSTableView` natively supports this; not wired to `UserDefaults` in Phase 2d.

5. **Automated headless render-FPS harness.** 120fps remains a manual Instruments gate; no windowless XCTest equivalent exists for GPU compositing.

6. **`FileRowView.isSelected` custom accent is not reactively bound to `Selection`.** PRE-EXISTING architectural gap, surfaced (not caused) by the `updateNSView` files-identity reload guard. `isSelected` is a plain `let` baked into the hosted `FileRowHost` at `FileRowHostingCell.configure(...)` time. On a selection-only change (no files change), `reloadData()` is correctly skipped, so cells are not reconfigured and the custom `.background(isSelected ? accent.opacity(0.18) : .clear)` does not refresh for affected rows. **NSTableView's native row-selection highlight still shows selection correctly** — this is a cosmetic secondary-accent staleness, not a "can't see selection" defect; it self-corrects on the next directory load/navigation. Before the guard, the over-reload bug incidentally masked this. Phase 3 fix: make `FileRowView`/`FileRowHost` observe `Selection<String>` reactively (inject it and read `selection.ids.contains(file.id)` in the body), or `tableView.reloadRows(at:)` on selection deltas. **The manual interaction ⏳ gate should specifically check whether the stale custom accent + native highlight produce a visible double-styling glitch during mixed mouse/keyboard selection on a static directory.**

### Phase 2c-discovered carry-forwards (still open)

6. **`FileProviderBridge.wasRecentlyEvicted` SDK gap.** macOS 26 SDK does not expose `enumeratorForEvictedItems`. Method is async with `// TODO Phase 3` marker. Phase 3 should revisit when Apple ships the API.

7. **`isItemMaterialized` basename collision.** Documented in the bridge's doc comment. Acceptable for the badge surface — Phase 3 improvement.

8. **`isItemMaterialized` 32-page cap.** `logger.warning` fires when hit; Phase 3 can raise the cap.

### Strategic-doc carry-forwards (eligible for Phase 3)

- **`RcloneSection` Version + Restart rows** — waiting on `RcloneDaemon` API additions.
- **OAuth re-authentication on Reconnect** — Phase 4. Reconnect re-fires the probe but does not initiate token refresh.

### Inherited from Phase 2a / Phase 1 (still open)

- **`ConfigForm` Name-row duplication in `EditRemoteSheet`.** Task 5 (Phase 2a) inlined Configuration + Advanced sections without the Name row. Future: add `showsNameRow: Bool` parameter.
- **`LocalizedStringKey(runtime-string)`** for some provider option labels — Phase 3 localization work.
- **`OnboardingView` verbatim-variant** — three call sites with runtime-string `LocalizedStringKey`. Fix: widen `OnboardingCard.message` to support a verbatim variant.
- **`NimbusUITests` XCUITest target** — Phase 1 carry-forward; not yet addressed.

## What's next

Phase 2d → **Phase 3** (system integration depth — Quick Look provider, Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish, notifications, OAuth re-auth on Reconnect, asc/desc sort UI in `BrowserToolbar`).
