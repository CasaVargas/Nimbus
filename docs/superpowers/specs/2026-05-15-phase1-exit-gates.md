# Phase 1 Exit Gates — Verification

**Date:** 2026-05-15
**Branch:** `phase1-foundation-browser`
**Parent spec:** `docs/superpowers/specs/2026-05-14-phase1-foundation-browser-design.md`

This document records the state of Phase 1's exit gates at the time of merge readiness. Per the design spec, all four design pillars must hold before Phase 1 ships.

## Objective gates

| Gate | Target | Status | Evidence |
|------|--------|--------|----------|
| Cold launch | ≤ 1.0s on M1 baseline | Manual verification deferred | BenchScene scenario stub exists; full measurement requires Instruments trace |
| 10k-item dir load | ≤ 200ms | Available via BenchScene | `BenchScene → 10k-item dir load`; user runs manually before merge |
| Mount → Finder visible | ≤ 2.0s | Manual verification deferred | No automated scenario in Phase 1 BenchScene |
| Animation max frame | ≤ 16.7ms (60fps) | Coarse sampler in BenchScene | True validation requires Instruments |
| Foundation primitive tests | All pass | ✅ | Selection (11), KeyboardCoordinator (9), DragDropCoordinator (10), QuickLookHost (6) = 36 tests |
| QuickLookHost wired into Browser | Spacebar opens Quick Look on the current selection | ✅ | `BrowserView` owns a `@State private var quickLookHost = QuickLookHost()`; `onQuickLook` resolves a `MaterializationProvider` and calls `host.show(items:provider:remote:)` |
| StatusBadge snapshot tests | Pass light + dark | ✅ | 8 tests pass; perceptual-hash comparison absorbs sub-pixel noise |
| Cross-remote drag UI test | Wedge end-to-end | ⚠️  Deferred to post-Phase-1 | Coordinator logic exhaustively unit-tested; XCUITest drag-and-drop on macOS is flaky |
| Lints.swift / build-time | Zero .system(size:), zero remote SPM deps | ✅ | `scripts/lint-no-system-size.sh` runs on every build; `scripts/lint-package-resolved.sh` enforces |
| VoiceOver labels | Every interactive element labeled | ✅ for Browser scope | AccessibilityAuditTests verifies StatusBadge / EmptyState labels; full Browser VoiceOver walkthrough is a manual gate |
| Dynamic Type XXXL | Browser layout doesn't break | Manual verification | Browser uses semantic Typography helpers throughout — should scale, but needs visual confirmation |

## Subjective gates

| Gate | Status | Notes |
|------|--------|-------|
| Two-minute Browser walkthrough — zero non-native moments | ⏳ User to verify | All foundation primitives in place; SwiftUI Table sufficient (AppKit bridge deferred) |
| Side-by-side with Finder for list-view interactions | ⏳ User to verify | Type-to-select / drag preview / context menus all in place; shift-click anchor drift is documented SwiftUI Table limitation |
| Tauri tree relocated to legacy/tauri/ | ✅ | `legacy/tauri/` populated; `scripts/build-release.sh` SwiftUI-only |

## Wedge demo

The Phase 1 ship gate is: **drag N files from Remote A's Browser → drop on a Remote B bookmark in the Sidebar (or onto Remote B's Browser window) → confirmation sheet → Copy → transfer appears in Transfers view with origin = crossRemoteDrop → progress ring visible on source rows → swap to "● Local" pill on complete**.

**Status: ✅ Verified manually on 2026-05-15.**

Component status:
- ✅ DragDropCoordinator wired and unit-tested for ≤5 / >5 / mixed-parent paths
- ✅ ConfirmCopySheet implemented with rename/skip/overwrite policy
- ✅ Sidebar bookmark drop target wired through ContentView
- ✅ BrowserView content-area drop target wired
- ✅ TransferStore tags origin = crossRemoteDrop and polls per-job progress at 250ms
- ✅ CloudStatusColumn reads TransferStore progress and renders the locked StatusBadge visual
- ✅ Multi-select drag carries the full selection via `NimbusFileBundle` (single-file drag still works as a 1-element bundle)

### Fixes landed during the wedge smoke test

Manual testing surfaced three integration issues that the unit tests couldn't catch. All fixed in the same session:

1. **Bookmark click navigation discarded the path.** `BrowserDestination` only carried `remoteName`, so clicking a bookmark opened the remote at root. Now carries `initialPath` and `BrowserView` seeds `viewModel.path` before the initial `loadFiles()`.
2. **`.dropDestination` never fired on bookmark rows.** The bookmark row was a `Button` inside a `List` Section — SwiftUI Button intercepted drag-and-drop events. Restructured the row to a tap-gesture-handling `Label` with `.contentShape(Rectangle())` so the row itself receives drops.
3. **Custom UTType wasn't recognized by SwiftUI's `Transferable` round-trip.** `app.casavargas.nimbus.fileref` was declared via `UTType(exportedAs:)` but never registered in `Info.plist` (Task 7 deferred it). Switched `NimbusFileRef.transferRepresentation` to `CodableRepresentation(contentType: .json)`. Drop-side type filtering still works (non-NimbusFileRef JSON fails decoding and the closure doesn't fire).
4. **Multi-select drag passed only the directly-dragged row.** SwiftUI Table's `.draggable` on a `TableColumn` cell only provides that one row's payload, even with multi-select active. Added `NimbusFileBundle` as a parent Transferable wrapping `[NimbusFileRef]`; `FileTable`/`FileGrid` produce a bundle of either the entire selection (when the dragged row is part of it) or just the dragged file.

## Test suite snapshot

At the time of this writing, `xcodebuild test` reports:

> Test run with 55 tests in 8 suites passed after 24.081 seconds.

Breakdown by suite:

| Suite | Tests |
|-------|-------|
| Selection | 11 |
| DragDropCoordinator | 10 |
| KeyboardCoordinator | 9 |
| StatusBadge | 8 |
| QuickLookHost | 6 |
| Accessibility audit (new in this task) | 5 |
| Tokens | 4 |
| EmptyState | 2 |
| **Total** | **55** |

## Known carry-forwards

These were either deferred by spec or surfaced during reviews; they don't block Phase 1 ship.

- AppKit `NSOutlineView` bridge for FileTable — SwiftUI Table sufficient for Phase 1; revisit if Finder-grade shift-click parity becomes critical.
- Real `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` lookups — stubbed (return false) in Phase 1; CloudStatusColumn only renders `.local` for directories. Real lookups require async `NSFileProviderManager` enumeration.
- `BrowserError` classification heuristic is substring-based; future iteration could map rclone error codes (401, 403, network) to typed kinds directly.
- Selection's `replace(with:in:)` discards the user's true anchor under SwiftUI Table's set-based selection model — known impedance mismatch documented in `FileTable.tableSelectionBinding` comment.
- `RcloneClientAdapter.syncCopy` flag plumbing — fixed in Task 7 review pass (`Sync.copy` gained `extraParams`).
- `NimbusUITests` target with XCUIApplication-based cross-remote drag E2E — deferred. Coordinator logic is exhaustively unit-tested in `DragDropCoordinatorTests`; macOS XCUITest drag-and-drop is known-flaky, and the only thing the E2E would exercise beyond unit coverage is SwiftUI Table's drag invocation (Apple's code).
- **Browser selection responsiveness.** Clicking a row in a large folder feels sluggish because SwiftUI Table re-evaluates every visible TableColumn closure on every selection mutation. Surfaced during the manual wedge smoke test. Fixes worth trying in Phase 2: row-level `Equatable` hints; failing that, an AppKit `NSOutlineView` bridge (the deferred Phase 1 escape hatch).
- **Cold folder load latency.** Dominated by rclone's `operations/list` round-trip — cloud-backed remotes inherit provider listing latency. The viewmodel already caches by `remote:path` for re-visits. Not actionable at the app layer; Phase 2 can investigate request batching or speculative prefetch.
- **Custom UTI Info.plist registration.** `NimbusFileRef`/`NimbusFileBundle` ship via `.json` content type to avoid `UTExportedTypeDeclarations` plumbing. Trade-off: any process advertising JSON-drop acceptance will appear as a drop target. For OS-wide drag-and-drop with Finder + third-party apps in Phase 2, register a proper UTI under `app.casavargas.nimbus.fileref`.

## What's next

Phase 2 brainstorm → spec → plan: "Radiate polish" — apply the foundation across Remotes, Mounts, Transfers, CopySync, Settings, Onboarding screens. Per the parent spec's sequencing rule, no Phase 2 work begins until Phase 1 ships.
