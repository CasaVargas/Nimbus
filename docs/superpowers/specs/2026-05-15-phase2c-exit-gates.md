# Phase 2c Exit Gates — Verification

**Date:** 2026-05-15
**Branch:** `phase2c-state-accuracy`
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`
- `docs/superpowers/specs/2026-05-15-phase2c-state-accuracy-design.md`

**Parent plan:** `docs/superpowers/plans/2026-05-15-phase2c-state-accuracy.md`

Records the state of Phase 2c's exit gates at the time of merge readiness. Per the strategic doc, all four design pillars must hold for the three affected screens (Remotes / Mounts / Browser) before Phase 2c ships.

## Objective gates

| Gate | Target | Status | Evidence |
|------|--------|--------|----------|
| CRITICAL carry-forward #1 resolved — `NimbusApp.startApp()` uses `mountConfig(_:)` | Replaces direct `mount(remote:mountPoint:readOnly:)` call so `mountedIDs` bookkeeping stays consistent | ✅ | Task 1 (`56eea59`): `startApp()` now calls `mountManager.mountConfig(config)` for each auto-mount config; `mountedIDs` populated correctly at launch |
| CRITICAL carry-forward #2 resolved — `CopySyncViewModel.error` typed as `NimbusError?` | Migrate from `String?` to `NimbusError?`; `CopySyncView` reads `.message` | ✅ | Task 2 (`7d9a6bc`): `error: NimbusError?` replaces `String?`; `CopySyncView` updated to display `.message` |
| `RemoteStatus.unknown` added | Pre-probe state with `"○ Checking…"` pill | ✅ | Task 3 (`1e25de7`): `RemoteStatus.unknown` case added; `RemoteRow` pill shows `"Checking…"` while probe is in-flight |
| `RemoteStatusService` exists with 11 passing tests | Per-remote `operations/about` probes; service injected into environment | ✅ | Task 4 (`9366ac8b`): `RemoteStatusService` implemented; 11 tests in `RemoteStatusServiceTests` suite all pass |
| `RemoteRow.status` reads real service state | Bound to `RemoteStatusService`; no hardcoded `.connected` | ✅ | Task 5 (`2c5ac8da`): `RemotesView` injects `RemoteStatusService`; `RemoteRow.status` driven by service's `status(for:)` |
| `reconcileFPDomains` pure function + 4 passing tests | Accepts current domains + target configs; returns add/remove sets | ✅ | Task 6 (`e9635ad`): `reconcileFPDomains(_:matching:)` implemented as a pure free function; 4 tests in `reconcileFPDomains` suite all pass |
| `MountManager.refreshAll()` real implementation | Calls `cleanupStaleMounts()` + `reconcileFPDomains`; no longer a stub | ✅ | Task 7 (`a14e6e5c`): `MountManager.refreshAll()` runs stale-mount cleanup and FP domain reconciliation using `reconcileFPDomains` |
| `TimedCache` exists with 3 passing tests | Generic per-folder TTL cache with 5 s expiry | ✅ | Task 8 (`d569065`): `TimedCache<K, V>` implemented; 3 tests in `TimedCache` suite all pass |
| `FileProviderBridge.isItemMaterialized` async + real | Uses `enumeratorForMaterializedItems()` with `TimedCache` to check real FP state | ✅ | Task 9 (`beb515d`): `isItemMaterialized` walks the real materialized-items enumerator (up to 32 pages, cached 5 s); replaces placeholder `false` |
| `FileProviderBridge.wasRecentlyEvicted` async + STUBBED | Async signature is forward-compatible; impl returns `false` | ⚠️ | Task 9 contingency: macOS 26 SDK does not expose `enumeratorForEvictedItems`. Method is async with a `// TODO Phase 3` marker. Carry-forward — see Known Carry-forwards below. |
| Page-cap comment + truncation warning | `logger.warning` fires when materialized enumerator hits the 32-page cap | ✅ | Task 10 (`fe1de95`): cap comment clarified; `logger.warning("Materialized enumerator hit page cap …")` added |
| Full test suite | 105 tests, 0 failures | ✅ | **105 tests in 20 suites passed after 0.795 seconds** |
| Build-time lints green | `lint-no-system-size: OK`, `lint-package-resolved: OK` | ✅ | Both lint hooks output OK on clean build |
| `Package.resolved` unchanged | No new SPM dependencies | ✅ | No `Package.resolved` file exists; no remote SPM deps added in Phase 2c |
| VoiceOver labels on new status pills | `RemoteStatus.unknown` pill accessible | ⏳ User to verify | `RemoteRow` pill uses `.accessibilityLabel` reflecting the status display string; full VoiceOver runtime walk needed |
| Manual smoke — Remotes shows real status | `RemoteRow` transitions through `.unknown` → resolved state | ⏳ User to verify | See Wedge / Manual smoke section below |
| Manual smoke — Reconnect retries one row | Reconnect re-fires `RemoteStatusService` probe for that remote | ⏳ User to verify | See Wedge / Manual smoke section below |
| Manual smoke — `refreshAll` picks up existing mount | `MountManager.refreshAll()` reconciles FP domains against `MountConfigStore` | ⏳ User to verify | See Wedge / Manual smoke section below |

## Subjective gates

| Gate | Status | Notes |
|------|--------|-------|
| HIG side-by-side — Remotes ↔ Finder cloud volumes | ⏳ User to verify | `RemoteRow` now drives status from `RemoteStatusService`. Status pills (`.unknown` / `.connected` / `.authNeeded` / `.error`) use semantic `DesignSystem` colors and SF Symbols. The Reconnect context-menu item re-fires the probe — matching the iCloud "Re-try" affordance in Finder's sidebar. No custom chrome; pill is a native `Label` tinted by status. |
| HIG side-by-side — Mounts ↔ Disk Utility | ⏳ User to verify | `MountManager.refreshAll()` reconciliation makes each `MountRow`'s mounted/unmounted state authoritative — matching Disk Utility's live volume list. FP domains are added and removed to stay in sync with `MountConfigStore.configs`. No stale rows remain after a refresh cycle. |
| HIG side-by-side — Browser ↔ Finder cloud badges | ⏳ User to verify | `FileProviderBridge.isItemMaterialized` now reflects real FP materialization state for items in FP-mounted directories (cloud icon for never-downloaded, checkmark for materialized). Badge is a hint surface (basename-collision edge case documented), matching Finder's best-effort cloud-status badges. |
| All four design pillars hold for the affected screens | ⏳ User to verify | **Native-or-nothing:** `RemoteStatusService` uses only `URLSession` + `RcloneKit`; no third-party deps. **Finder-grade interaction:** Status pills + Reconnect item match Finder cloud-volume affordances. **Utility-app rigor:** `TimedCache`, `reconcileFPDomains`, and `RemoteStatusService` are focused single-responsibility primitives, each independently tested. **Performance is a feature:** `TimedCache` (5 s TTL) prevents redundant FP enumerator walks per folder; `RemoteStatusService` probes are async and non-blocking on the main thread. |

## Wedge / Manual smoke

Phase 2c's user-visible wedge is the Remotes status flow:

1. Launch with a remote that is known-bad (revoked OAuth or invalid credentials).
2. Open the Remotes tab — the row should show `○ Checking…` briefly while `RemoteStatusService` fires the `operations/about` probe, then transition to `⚠ Sign In` once the probe fails.
3. Right-click → **Reconnect** — the row re-runs the probe and ends in `⚠ Sign In` again. (No real OAuth refresh in Phase 2c; Reconnect re-fires the probe only. OAuth re-auth is Phase 4.)
4. Quit Nimbus, fix the credentials via `rclone config`, then relaunch — the row should now show `● Connected` once the fresh probe succeeds.
5. Navigate to the Browser for an FP-mounted remote — file badges should reflect real materialization state: cloud icon for items never downloaded, checkmark for items materialized locally.

**Status:** ⏳ Manual verification pending — user runs once before merge.

## Component status

- ✅ `RemoteStatusService` — per-remote `operations/about` probes with async status publishing; 11 tests
- ✅ `RemoteStatus.unknown` — pre-probe state; `RemoteRow` pill shows `"Checking…"` with a neutral glyph
- ✅ `MountManager.refreshAll()` — real reconciliation: `cleanupStaleMounts()` + `reconcileFPDomains`; no longer a no-op stub
- ✅ `reconcileFPDomains` — pure free function accepting current FP domains + target configs, returning add/remove sets; 4 tests
- ✅ `TimedCache` — generic per-folder 5 s TTL cache preventing redundant FP enumerator walks; 3 tests
- ✅ `FileProviderBridge.isItemMaterialized` — async; real implementation walks `enumeratorForMaterializedItems()` up to 32 pages, cached via `TimedCache`
- ⚠️ `FileProviderBridge.wasRecentlyEvicted` — async signature (forward-compatible); implementation stubs `return false` with `// TODO Phase 3` — macOS 26 SDK does not expose `enumeratorForEvictedItems`
- ✅ `NimbusApp.startApp()` — auto-mount now calls `mountManager.mountConfig(_:)` ensuring `mountedIDs` consistency; `refreshAll()` called after startup mounts complete
- ✅ `CopySyncViewModel.error` — typed `NimbusError?`; `CopySyncView` displays `.message`

## Test suite snapshot

`xcodebuild test -scheme Nimbus`:

> Test run with 105 tests in 20 suites passed after 0.795 seconds.

Breakdown:

| Suite | Tests | Phase |
|-------|-------|-------|
| **RemoteStatusService** | **11** | **✅ Phase 2c (Task 4)** |
| **reconcileFPDomains** | **4** | **✅ Phase 2c (Task 6)** |
| **TimedCache** | **3** | **✅ Phase 2c (Task 8)** |
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
| Selection | 11 | Phase 1 baseline |
| KeyboardCoordinator | 9 | Phase 1 baseline |
| DragDropCoordinator | 10 | Phase 1 baseline |
| QuickLookHost MaterializationProvider selection and cleanup | 6 | Phase 1 baseline |
| Accessibility audit | 5 | Phase 1 baseline |
| **Total** | **105** | **Phase 1 (55) + Phase 2a (+27) + Phase 2b (+5) + Phase 2c (+18)** |

## Known carry-forwards into next phases

### Phase 2c-discovered

1. **`FileProviderBridge.wasRecentlyEvicted` SDK gap.** macOS 26 SDK does not expose `enumeratorForEvictedItems`. The method has an async signature (forward-compatible) but returns `false` with a `// TODO Phase 3` comment. Phase 3 should revisit when Apple ships the API. An alternative signal worth exploring: `NSFileProviderManager.evictItem(identifier:completionHandler:)` is the inverse operation (it triggers eviction) — it does not expose a read-side query, but monitoring eviction callbacks via the File Provider protocol may provide a usable signal.

2. **`isItemMaterialized` basename collision.** Two distinct paths sharing the same filename within the same remote (e.g. `/A/Report.pdf` and `/B/Report.pdf`) will both report as materialized if either one is materialized. This is documented in the bridge's doc comment. Acceptable for the badge surface — it is a hint, not a contract. Phase 3 could improve accuracy by walking parent-identifier chains, but the traversal cost is significant and the improvement is cosmetic.

3. **`isItemMaterialized` 32-page cap.** The materialized-items enumerator walk stops at 32 pages. Items beyond that threshold do not appear in the cache and surface stale (un-materialized) badges. Domains with very large materialized sets are affected. A `logger.warning` fires when the cap is hit, making the condition diagnosable in Console. Phase 3 can raise or remove the cap if large-domain users report stale badges.

### Strategic-doc carry-forwards (eligible for Phase 2d / Phase 3)

- **Browser `NSOutlineView` AppKit bridge** — Phase 2d. Virtual row recycling for large directory listings.
- **`RcloneSection` Version + Restart Daemon rows** — waiting on `RcloneDaemon` API additions (`rcloneVersion` property, `restart()` method).
- **OAuth re-authentication flow on Reconnect** — Phase 4. Reconnect in Phase 2c re-runs the `operations/about` probe but does not initiate token refresh. A real OAuth re-auth flow requires a browser handoff or embedded web view.

### Inherited from Phase 2a / Phase 1 (still open)

- **`ConfigForm` Name-row duplication in `EditRemoteSheet`.** Task 5 (Phase 2a) inlined Configuration + Advanced sections without the Name row rather than parametrizing `ConfigForm`. A future refactor could add `showsNameRow: Bool`.
- **`LocalizedStringKey(runtime-string)` for some provider option labels** — explicitly noted as Phase 3 work in `ConfigForm`. Real localization extraction will need either an overload taking `String` or a separate localization layer.
- **`OnboardingView` `LocalizedStringKey(runtime-string)`** at three call sites: daemon-error message, connected-remote name interpolation, mounted-path interpolation. Fix: widen `OnboardingCard.message` to support a verbatim variant (mirror `EmptyState.messageVerbatim`).
- **`UTExportedTypeDeclarations`, `NimbusUITests` XCUITest target** — Phase 1 carry-forwards; not yet addressed.

## What's next

Phase 2c → **Phase 2d** (Browser perf — `NSOutlineView` AppKit bridge + virtualized rows) → Strategic-doc **Phase 3** (system integration depth — Quick Look provider, Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish, notifications, OAuth re-auth on Reconnect).
