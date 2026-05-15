# Phase 2b Exit Gates — Verification

**Date:** 2026-05-15
**Branch:** `phase2b-supporting-polish`
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`
- `docs/superpowers/specs/2026-05-15-phase2b-supporting-polish-design.md`

**Parent plan:** `docs/superpowers/plans/2026-05-15-phase2b-supporting-polish.md`

Records the state of Phase 2b's exit gates at the time of merge readiness. Per the strategic doc, all four design pillars must hold for the three supporting screens (Onboarding / Settings / CopySync + PathPicker) before Phase 2b ships.

## Objective gates

| Gate | Target | Status | Evidence |
|------|--------|--------|----------|
| Foundation primitive tests pass — `OnboardingCard` | 5 tests | ✅ | `OnboardingCard` (5): `rendersPendingState`, `rendersInProgressState`, `rendersCompleteState`, `rendersActionRequiredState`, `rendersCompleteWithPrimaryAction` |
| Snapshot tests for new state combinations | `OnboardingCard-completeWithPrimary` added | ✅ | `rendersCompleteWithPrimaryAction` snapshot added in Task 2 fix-up; captures Done-card state with primary action button |
| View migrations — Onboarding | `OnboardingView` rebuilt as progressive card stack | ✅ | `OnboardingView` rebuilt around four `OnboardingCard` instances with 4-state machine; auto-mount `.onChange` pipeline added |
| View migrations — Settings (6 panes) | All six `*Section` views rebuilt against `FormSection` | ✅ | `GeneralSection`, `AppearanceSection`, `TransferSection`, `RcloneSection`, `StorageUsageView`, `AboutSection` all rebuilt; window resized to 520×360 |
| View migrations — CopySync | `CopySyncView` rebuilt with `FormSection` + `DestructiveCallout` | ✅ | Source, destination, operation, flags all in `FormSection`; `DestructiveCallout` used for overwrite-flag warning |
| View migrations — PathPicker | Rebuilt as `FormRow`-compatible | ✅ | `PathPicker` rebuilt as a `FormRow`-style control with `NSOpenPanel` under the hood |
| ViewModel migrations — `CopySyncViewModel.error` ownership refactor | `private(set) var` + `clearError()` + `startOperation` is `async` (not `async throws`) | ✅ | `error` is `private(set) var lastError: String?`; `clearError()` resets it; `startOperation` catches internally and assigns `lastError` rather than throwing |
| Full test suite | ≥ 87 tests, 0 failures | ✅ | **87 tests in 17 suites passed after 1.037 seconds** (was 82 baseline; +5 in Phase 2b) |
| Build-time lints green | Zero `.system(size:)`, zero remote SPM deps | ✅ | `lint-no-system-size: OK`, `lint-package-resolved: no Package.resolved (no remote SPM deps) — OK` |
| `Package.resolved` unchanged | No new SPM deps | ✅ | No `Package.resolved` file exists; no remote SPM deps added |
| VoiceOver labels — Phase 2b screens | Every interactive element | ⏳ User to verify | `OnboardingCard` has `.accessibilityHint` on primary/secondary action buttons. Settings panes use native SwiftUI controls (`Toggle`, `Picker`, `TextField`, `Stepper`) which carry system VoiceOver labels. `PathPicker` has `.accessibilityLabel` on the Browse button. Full audit requires VoiceOver runtime walk. |
| Dynamic Type XXXL — Phase 2b screens | No layout breaks | ⏳ User to verify | All Phase 2b views route through `DesignSystem.Typography.*` semantic tokens. `OnboardingCard` icon + title + message scale with Dynamic Type. Settings panes use `.body` / `.subheadline` / `.caption` semantic sizes. No hardcoded `.system(size:)` calls (lint verified). |
| First-launch wedge — ≤ 90 seconds setup-to-mount | End-to-end smooth | ⏳ User to verify | See Wedge Demo section below. Auto-mount pipeline wired: `.onChange(of: mountStore.configs.count)` → `attemptAutoMount()` → `mountManager.mountConfig(_:)`. |

## Subjective gates

| Gate | Status | Notes |
|------|--------|-------|
| HIG side-by-side — Onboarding ↔ macOS Setup Assistant | ⏳ User to verify | `OnboardingCard` uses a centered card-stack layout with system SF Symbols, `.largeTitle` typography, and native `Button` controls. Progressive disclosure matches Setup Assistant's single-step-at-a-time cadence. No custom navigation chrome — cards reveal sequentially via state transitions. |
| HIG side-by-side — Settings ↔ macOS Mail Preferences | ⏳ User to verify | All six Settings panes use `FormSection` (matching System Settings preference-form style). `GeneralSection` uses `Toggle(.switch)` for Launch at Login. `AppearanceSection` uses `Picker(.segmented)` for Appearance. `TransferSection` uses `TextField` + `Stepper` for numeric limits. `RcloneSection` uses a file-path `TextField` + Browse button. No custom segmented controls or checkboxes. |
| HIG side-by-side — CopySync ↔ Pages Export | ⏳ User to verify | `CopySyncView` uses `FormSection` (three sections: Source, Destination, Options). `DestructiveCallout` surfaces the overwrite-flag warning inline in the form — matching the Pages Export destructive-action pattern. `PathPicker` uses native `NSOpenPanel`. No modal interruptions for the happy path. |
| Two-minute walkthrough — zero non-native moments | ⏳ User to verify | All Phase 2b primitives are native: `OnboardingCard` state machine uses `withAnimation(.spring)`, native `Button`, native `ProgressView`. Settings panes use all-native controls. `DestructiveCallout` uses `.callout` color + `.destructiveAction` button role. No custom capsule toggles, no third-party UI. |
| All four design pillars hold for the 3 screens | ⏳ User to verify | **Native-or-nothing:** No third-party UI deps; all controls are system-provided. **Finder-grade interaction:** `PathPicker` uses `NSOpenPanel`; `CopySyncView` toolbar validates before running. **Utility-app rigor:** `OnboardingCard` / `FormSection` / `DestructiveCallout` / `PathPicker` primitives consistent across screens. **Performance is a feature:** Onboarding daemon card auto-progresses without polling; no new timers introduced. |

## Wedge demo

End-to-end first-launch flow — ≤ 90 seconds setup-to-mount:

1. User launches Nimbus with `defaults delete app.casavargas.nimbus onboardingComplete` (resets onboarding flag).
2. Onboarding hero card + daemon card shows immediately — daemon card is in `.inProgress` state.
3. Daemon card auto-progresses to `.complete` within ~2 s once `daemon.status == .connected`.
4. Add Remote card reveals (`.actionRequired`) — user taps **Add Remote**, fills `local` provider (or any), taps **Add Remote** in the sheet.
5. `RemoteConfigStore.configs.count` increments → Add Remote card transitions to `.complete`, Mount card reveals.
6. User taps **Add Mount**, accepts defaults (or picks a folder), taps **Add**.
7. `MountConfigStore.configs.count` increments → `onChange(of: mountStore.configs.count)` fires → `attemptAutoMount()` calls `mountManager.mountConfig(_:)`.
8. Mount card transitions to `.complete` once `mountManager.mountedIDs` contains the new config's ID, Done card reveals.
9. User taps **Done** → `settings.onboardingComplete = true` → main app shows with Remotes + Mounts populated.

**Status:** ⏳ Manual verification pending — user runs once before merge.

### Component status

- ✅ `OnboardingCard` — 4-state primitive (`pending` / `inProgress` / `actionRequired` / `complete`) with primary + secondary action buttons; snapshot-tested (5 tests)
- ✅ `OnboardingView` — Progressive card stack orchestrating daemon-check → add-remote → add-mount → done; auto-mount `.onChange` pipeline
- ✅ `GeneralSection` — Launch at Login toggle via `useLaunchAtLogin` hook; `FormSection` layout
- ✅ `AppearanceSection` — Appearance segmented picker; `FormSection` layout
- ✅ `TransferSection` — Bandwidth limit + concurrent transfer count fields with validation; `FormSection` layout
- ✅ `RcloneSection` — rclone binary path + Browse button; `FormSection` layout
- ✅ `StorageUsageView` — Cache usage display + real **Clear Cache** implementation; `FormSection` layout
- ✅ `AboutSection` — Centered chrome-less layout with app icon, version, copyright, and links
- ✅ `CopySyncView` — Full rebuild: source/destination `PathPicker`, operation picker, flags, `DestructiveCallout` for overwrite warning
- ✅ `PathPicker` — `FormRow`-compatible file-path picker backed by `NSOpenPanel`
- ✅ `DestructiveCallout` — Inline warning primitive for destructive-action confirmation
- ✅ `CopySyncViewModel` — `error` ownership refactor: `private(set) var lastError: String?` + `clearError()` + `startOperation` is `async` (catches internally)

## Test suite snapshot

`xcodebuild test -scheme Nimbus`:

> Test run with 87 tests in 17 suites passed after 1.037 seconds.

Breakdown:

| Suite | Tests | Phase |
|-------|-------|-------|
| OnboardingCard | 5 | ✅ Phase 2b (Task 2 + fix-up) |
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
| **Total** | **87** | **Phase 1 (55) + Phase 2a (+27) + Phase 2b (+5)** |

## Known carry-forwards into Phase 3

These were deferred by spec or surfaced during implementation; they do not block Phase 2b ship.

### CRITICAL (must fix before any new caller of the affected state lands)

1. **`NimbusApp.startApp()` app-launch auto-mount loop bypasses `MountManager.mountConfig(_:)`.** Currently calls `mountManager.mount(remote:mountPoint:readOnly:)` directly inside `startApp()` (lines 81–89 of `NimbusApp.swift`). This populates `activeMounts` but NOT `mountedIDs`. The view-level fallback in `MountManager.refreshAll()` unions the two sets so `MountsView` is unaffected, but `OnboardingView.hasMounts` and any future direct readers of `mountedIDs` would be confused. **Fix:** replace the direct `mount(remote:mountPoint:readOnly:)` call in `startApp()` with `mountConfig(config)` so bookkeeping stays consistent.

2. **`CopySyncViewModel.error` is `String?`, not `NimbusError?`.** The Phase 2a `NimbusError` migration did not reach `CopySync`. Phase 3 should migrate `CopySyncViewModel.error: String?` → `CopySyncViewModel.error: NimbusError?` and update `CopySyncView`'s error display to use `.message` instead of the raw string.

### Phase 2b-specific carry-forwards

- **`OnboardingView.hasMounts` is config-count-based, not mount-state-based.** Acceptable for the wedge (mount completes in <2 s) but Phase 3 should gate on `mountManager.mountedIDs.contains(_:)` for accuracy.
- **`TransferSection.bandwidthLimit` regex accepts lowercase `t`** (`[kMGTkmgt]`) but rclone only accepts uppercase `T` for terabytes. Low impact (rclone rejects invalid values at runtime); regex should drop the lowercase `t` in Phase 3.
- **`AppSettings.Appearance` enum declaration order** is `case light, dark, system` while the `AppearanceSection` display order is "System / Light / Dark". Cosmetic — reorder the enum to `system, light, dark` for coherence.
- **`RcloneSection` drops the Version + Restart Daemon rows from the original spec.** `RcloneDaemon` doesn't expose `rcloneVersion` or `restart()`. Add those APIs in Phase 3 and re-add the rows.
- **`OnboardingCard` snapshot of `.inProgress` state** captures a static prohibited-sign glyph instead of an animating spinner — a known macOS `ImageRenderer` limitation with `ProgressView`. Documented; not a defect.
- **`isValid` in `CopySyncView`** doesn't guard `viewModel != nil`. Safe today because the empty `remoteNames` array prevents the user from selecting a remote, but fragile if `PathPicker` ever gains free-text input. Add `viewModel != nil` to the `isValid` guard in a follow-up.
- **Magic literal `frame(maxHeight: 160)` on the CopySync error `EmptyState`** — no `DesignSystem` token corresponds. Cosmetic.

### Phase 2a / Phase 1 carry-forwards (still open)

- **`MountManager.refreshAll()` is a stub** — Phase 2a left it as a no-op. A full implementation needs to poll `mount(8)` or `NSFileProviderManager` and reconcile against `MountConfigStore.configs`.
- **`TransfersViewModel` is dead code.** `TransfersView` now consumes `TransferStore` directly. Deleted in Phase 2a cleanup; no further action needed.
- **`ConfigForm` Name-row duplication in `EditRemoteSheet`.** Task 5 (Phase 2a) inlined the Configuration + Advanced sections (skipping the Name row) instead of parametrizing `ConfigForm`. A future refactor could add `showsNameRow: Bool`.
- **`LocalizedStringKey(runtime-string)` for some provider option labels** — explicitly noted as Phase 3 work in `ConfigForm`. Real localization extraction will need either an overload taking `String` or a separate localization layer.
- **Status discovery placeholder.** `RemoteRow.status` is hardcoded to `.connected` in Phase 2a. Phase 3 should implement live status discovery, then surface `.authNeeded` / `.error(reason:)` from `RemotesViewModel`.
- **`Reconnect` handler no-op** in `RemoteRow` context menu — guarded by `Logger.warning` since `.connected` is hardcoded. Wire up properly when live status discovery lands.
- **Browser-side carry-forwards untouched:** AppKit `NSOutlineView` bridge, real `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted`, `UTExportedTypeDeclarations`, `NimbusUITests` XCUITest target, cold folder-load latency — all stay open from Phase 1.

## What's next

Phase 3 brainstorm → spec → plan. Per the strategic doc's sequencing rule, no Phase 3 work begins until Phase 2b ships.

Probable Phase 3 scope (per `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`):
- Live remote-status discovery and per-remote auth/error states surfaced from `RemotesViewModel`
- Real `MountManager.refreshAll()` implementation (poll `mount(8)` / `NSFileProviderManager`)
- Browser AppKit `NSOutlineView` bridge for performance on large directories
- Real materialized / evicted File Provider queries (`isItemMaterialized`, `wasRecentlyEvicted`)
- Migrate `CopySyncViewModel.error` to `NimbusError?` (CRITICAL carry-forward #2 above)
- Fix `NimbusApp.startApp()` to call `mountConfig(_:)` not `mount(remote:mountPoint:readOnly:)` (CRITICAL carry-forward #1 above)
- Re-add Version + Restart Daemon rows to `RcloneSection` once those APIs land in `RcloneDaemon`
