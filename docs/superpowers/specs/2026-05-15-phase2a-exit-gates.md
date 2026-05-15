# Phase 2a Exit Gates — Verification

**Date:** 2026-05-15
**Branch:** `phase2a-operational-polish`
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`
- `docs/superpowers/specs/2026-05-15-phase2a-operational-polish-design.md`

Records the state of Phase 2a's exit gates at the time of merge readiness. Per the strategic doc, all four design pillars must hold for the three operational screens (Remotes / Mounts / Transfers) before Phase 2a ships.

## Objective gates

| Gate | Target | Status | Evidence |
|------|--------|--------|----------|
| Foundation primitive tests pass | All | ✅ | `NimbusError` (5) + `SheetChrome` (2) + `FormSection` (2) + `StatusToggle` (4) + `ProgressMeter` (4) = 17 tests |
| Snapshot tests for screen rows | All | ✅ | `RemoteRow` (3) + `MountRow` (4) + `TransferRow` (3) = 10 snapshot tests |
| ViewModel migrations | Remotes / Mounts / Transfers / Browser → `NimbusError?` | ✅ | All four migrated; `BrowserError` is now a typealias of `NimbusError` |
| Full test suite | Pass | ✅ | **82 tests in 16 suites passed** (was 55 baseline; +27 in Phase 2a) |
| Build-time lints green | Zero `.system(size:)`, zero remote SPM deps | ✅ | `lint-no-system-size: OK`, `lint-package-resolved: no Package.resolved (no remote SPM deps) — OK` |
| `Package.resolved` unchanged | Yes | ✅ | No new SPM deps |
| VoiceOver labels present on Phase 2a screens | Every interactive element | ⏳ User to verify | `RemoteRow` / `MountRow` / `StatusToggle` / Toolbar items / Context menu items all have explicit `.accessibilityLabel` or rely on system controls' native labels. Full audit requires VoiceOver runtime walk. |
| Dynamic Type XXXL on Phase 2a sheets | No layout breaks | ⏳ User to verify | All views route through `DesignSystem.Typography.*` semantic tokens — should scale. Sheets: AddRemoteSheet, EditRemoteSheet, ImportConfigSheet, AddMountSheet. |

## Subjective gates

| Gate | Status | Notes |
|------|--------|-------|
| Two-minute walkthrough — zero non-native moments | ⏳ User to verify | All foundation primitives in place. `StatusToggle` uses native `Toggle(.switch)` (no custom Capsule/Circle). |
| Side-by-side with System Settings → Login Items (Mounts) | ⏳ User to verify | `MountRow` mirrors row layout + trailing switch + status-tinted icon. `StatusToggle` uses native control. |
| Side-by-side with Mail outbox (Transfers) | ⏳ User to verify | `TransferRow` mirrors leading-icon + name + truncated path + trailing progress/status. Two sections (Active / Recent). |
| Side-by-side with System Settings → Add Account (Add Remote) | ⏳ User to verify | `ProviderPicker` 96×96 tile grid. `ConfigForm` uses `FormSection` (System Settings preference-form style). |
| All four design pillars hold for the 3 screens | ⏳ User to verify | Native-or-nothing (StatusToggle reverted from custom to Toggle(.switch); no third-party UI deps); Finder-grade interaction (List selection on Remotes, hover/focus, context menus); Utility-app rigor (StatusBadge / EmptyState / FormSection / SheetChrome primitives consistent across screens); Performance is a feature (no new polling, no obvious perf regressions). |

## Wedge

**Setup-to-mount in ≤ 60 seconds, end-to-end smooth.**

End-to-end flow:
1. Open Nimbus → Remotes screen
2. Click **+ Add Remote** → `AddRemoteSheet` with `ProviderPicker` grid
3. Pick a provider (e.g., `local` for a quick test) → `ConfigForm`
4. Fill name + required fields → click **Add Remote**
5. New `RemoteRow` appears with `● Connected` status pill
6. Click **Mounts** in sidebar
7. Click **+ Add Mount** → pick the new remote + folder + accept defaults → click **Add**
8. New `MountRow` appears with `StatusToggle` in `.off`
9. Click the toggle → `.off → .mounting` (spinner overlay) → `.on` (filled accent color)
10. Finder shows the mount under Locations within ~2 seconds

**Status:** ⏳ Manual verification pending — user runs once before merge.

Component status:
- ✅ `AddRemoteSheet` rebuilt: two-step (ProviderPicker → ConfigForm), `SheetChrome` wrapper
- ✅ `RemoteRow` rebuilt: Disk Utility row pattern, status pill, context menu, List selection, VoiceOver actions
- ✅ `EditRemoteSheet` rebuilt: locked name field (read-only Text), Configuration + Advanced FormSections
- ✅ `ImportConfigSheet` decomposed: orchestrator + `ImportPreviewList` + `ImportRemoteRow`, `SheetChrome` wrapper, NSOpenPanel preserved
- ✅ `MountsView` rebuilt: `EmptyState` empty list, `MountRow` + `MountInspector` inline detail, toolbar Add Mount + Refresh
- ✅ `MountRow` + `MountInspector` rebuilt: System Settings Login-Items row pattern with status-tinted icon + `StatusToggle` trailing
- ✅ `AddMountSheet` rebuilt: `SheetChrome` + three `FormSection`s, doubles as Edit sheet via `editing:` parameter
- ✅ `StatusToggle` uses native `Toggle(.switch)` with `ProgressView` overlay for transitioning states
- ✅ `TransfersView` rebuilt: Active + Recent sections, filter Menu, Clear Completed
- ✅ `TransferRow` rebuilt: leading op-icon, src→dst subtitle, `ProgressMeter` trailing for active, status pill for completed/failed/cancelled
- ✅ `MountManager` extended with `mountedIDs`/`inFlight`/`errors`/`lastMounted` state + `mountConfig`/`unmountConfig` wrappers

## Test suite snapshot

`xcodebuild test -scheme Nimbus`:

> Test run with 82 tests in 16 suites passed after 0.761 seconds.

Breakdown:

| Suite | Tests | New in Phase 2a |
|-------|-------|-----------------|
| NimbusError | 5 | ✅ (Task 1) |
| SheetChrome | 2 | ✅ (Task 2) |
| FormSection | 2 | ✅ (Task 2) |
| RemoteRow | 3 | ✅ (Task 3) |
| StatusToggle | 4 | ✅ (Task 7) |
| MountRow | 4 | ✅ (Task 8) |
| ProgressMeter | 4 | ✅ (Task 10) |
| TransferRow | 3 | ✅ (Task 12) |
| Phase 1 baseline (Tokens, EmptyState, StatusBadge, Selection, KeyboardCoordinator, DragDropCoordinator, QuickLookHost, Accessibility audit) | 55 | — |
| **Total** | **82** | **+27** |

## Known carry-forwards into Phase 2b / Phase 3

These were deferred by spec or surfaced during reviews; they don't block Phase 2a ship.

- **`MountManager.refreshAll()` is a stub** — Phase 2a leaves it as a no-op. A full implementation needs to poll `mount(8)` or `NSFileProviderManager` and reconcile against `MountConfigStore.configs`. The current `state(for:)` derives liveness from `mountedIDs` set by `mountConfig`/`unmountConfig` wrappers, which is sufficient for the wedge.
- **`TransfersViewModel` is now dead code.** The new TransfersView consumes `TransferStore` directly. Worth deleting in a follow-up cleanup.
- **`ConfigForm` duplication in `EditRemoteSheet`.** Task 5 inlined the Configuration + Advanced sections (skipping the Name row) instead of parametrizing `ConfigForm`. A future refactor could add `showsNameRow: Bool` or extract `ProviderOptionField` into its own view.
- **`LocalizedStringKey(runtime-string)` for some provider option labels** — explicitly noted as Phase 3 work in `ConfigForm`. Real localization extraction will need either an overload taking `String` or a separate localization layer. Error messages already use `messageVerbatim:`.
- **Status discovery placeholder.** `RemoteRow.status` is hardcoded to `.connected` in Phase 2a. Phase 3 should implement live status discovery (e.g., per-remote ping or auth-check), then surface `.authNeeded` / `.error(reason:)` from `RemotesViewModel`.
- **`Reconnect` handler no-op** in `RemoteRow` context menu — guarded by `Logger.warning` since `.connected` is hardcoded. Wire up properly when live status discovery lands.
- **Browser-side carry-forwards untouched:** AppKit `NSOutlineView` bridge, real `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted`, `UTExportedTypeDeclarations`, `NimbusUITests` XCUITest target, cold folder-load latency — all stay open from Phase 1.

## What's next

Phase 2b brainstorm → spec → plan: CopySync + Settings + Onboarding screens. Same depth (deep HIG audit) and approach (sequential per-screen, JIT primitive extraction). Per the strategic doc's sequencing rule, no Phase 2b work begins until Phase 2a ships.
