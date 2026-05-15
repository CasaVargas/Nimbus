# Phase 2a: Operational Screens Polish

**Date:** 2026-05-15
**Status:** Draft
**Parent:** [Nimbus North Star](./2026-05-14-nimbus-north-star-design.md)
**Predecessor:** [Phase 1: Foundation + Browser](./2026-05-14-phase1-foundation-browser-design.md)
**Type:** Implementation design (first half of strategic Phase 2; Phase 2b follows)
**Scope:** Apply the Phase 1 foundation across the three operational screens (Remotes, Mounts, Transfers) with a deep HIG audit per screen. Extract shared primitives JIT into `Components/`/`State/`. Verify a setup-to-mount wedge end-to-end before merge.

---

## Why split Phase 2 into 2a + 2b?

The parent strategic doc scoped Phase 2 as "apply foundation to Remotes, Mounts, Transfers, CopySync, Settings, Onboarding" and noted "one spec or split per screen." With the chosen polish depth (deep HIG audit per screen, ~3–5 days each), six screens is 18–30 days of work — too large for one spec cycle to coordinate without drift.

Splitting:

- **Phase 2a** (this doc) — Remotes, Mounts, Transfers. The three screens users hit daily. Setup-to-mount is the wedge that ties them together.
- **Phase 2b** (separate later spec) — CopySync, Settings, Onboarding. Configuration and first-touch screens. Brainstorm/spec/plan kicks off after Phase 2a ships.

This split was a brainstorm decision, not a strategic-doc revision; the North Star's "one spec or split per screen" gives explicit license.

---

## Goals

1. **Three operational screens cleared to HIG-grade.** Remotes, Mounts, Transfers each pass a side-by-side comparison with the relevant Apple reference (Disk Utility / System Settings → Login Items / Mail outbox-while-sending).
2. **Shared primitives extracted JIT.** `NimbusError`, `FormSection`, `SheetChrome`, `StatusToggle`, `ProgressMeter` land in `Components/`/`State/` as their first consumer needs them — not built upfront.
3. **Setup-to-mount wedge works end-to-end** in under 60 seconds with zero non-native moments.
4. **All four design pillars hold** for the three screens at exit.

## Non-Goals

Explicitly **not** in Phase 2a:

- Onboarding, CopySync, Settings — Phase 2b.
- Browser perf hardening, AppKit `NSOutlineView` bridge — Phase 1 carry-forwards; Browser-only, not touched here.
- Real `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` — only consumer is `CloudStatusColumn` in Browser. Carry-forward stays open.
- `UTExportedTypeDeclarations` Info.plist registration — not needed for the setup-to-mount wedge.
- `NimbusUITests` target — same flakiness reasoning as Phase 1. Coordinator logic stays in unit tests.
- Tier 2 features (encryption wizard, scheduled syncs, public links) — Phase 4.

---

## Architectural Decisions

Locked during the brainstorm session that produced this doc.

| Decision | Choice | Reason |
|----------|--------|--------|
| Phase 2 split | 2a (Remotes/Mounts/Transfers) → 2b (CopySync/Settings/Onboarding) | Six screens × deep HIG = too large for one cycle. Split by user-frequency. |
| Polish depth | Deep HIG audit per screen | User picked the most ambitious option; "feels Apple-made" is the wedge. |
| Approach | Sequential per-screen with shared wedge | One spec/plan; screens land sequentially. JIT primitive extraction. |
| Wedge entry | Remotes (post-onboarding) | Keeps Phase 2a scope tight to the three operational screens. Onboarding polish lands in Phase 2b. |
| `StatusToggle` implementation path | SwiftUI first; fall back to `NSViewRepresentable` over `NSSwitch` if SwiftUI Toggle can't match System Settings' look | Same pragmatism as the Phase 1 `Table` decision. |

---

## File structure changes

New / changed files. Rough file structure under `Nimbus/Nimbus/`:

```
Components/                      # existing — additions in this phase
  FormSection.swift              # NEW — Apple-style preference-form wrapper
  SheetChrome.swift              # NEW — header/body/action-bar sheet layout
  StatusToggle.swift             # NEW — mount switch with .off/.mounting/.on/.error states
  ProgressMeter.swift            # NEW — linear-bar variant of StatusBadge ring

State/                           # existing — additions
  NimbusError.swift              # NEW — typed error generalizing BrowserError

ViewModels/                      # existing — migrations
  RemotesViewModel.swift         # error: String? → NimbusError?
  MountsViewModel.swift          # error: String? → NimbusError?
  TransfersViewModel.swift       # error: String? → NimbusError?
  BrowserViewModel.swift         # BrowserError → NimbusError alias or full migration

Views/Remotes/                   # REBUILT
  RemotesView.swift              # DesignSystem tokens, EmptyState, skeleton load, NimbusError surfacing
  RemoteRow.swift                # Disk Utility-grade row, status pill, hover affordances
  AddRemoteSheet.swift           # SheetChrome + two-step (ProviderPicker → ConfigForm)
  EditRemoteSheet.swift          # SheetChrome + FormSection
  ImportConfigSheet.swift        # decomposed orchestrator (≤120 LOC)
  ImportPreviewList.swift        # NEW — per-row include/exclude toggles
  ImportConflictRow.swift        # NEW — existing-name collision handler
  ConfigForm.swift               # rebuilt as FormSection consumer
  ProviderPicker.swift           # NEW — Apple "Add Account" grid pattern

Views/Mounts/                    # REBUILT
  MountsView.swift
  MountRow.swift                 # System Settings Login-Items row pattern + inline inspector
  MountInspector.swift           # NEW — expandable detail pane under selected row
  AddMountSheet.swift

Views/Browser/                   # MODIFIED (small)
  ConfirmCopySheet.swift         # retroactively wrapped in SheetChrome for consistency
```

Test additions: snapshot fixtures for `RemoteRow` (3 states), `MountRow` (4 `StatusToggle` states), `TransferRow` (3 variants), plus unit tests for `NimbusError`, `FormSection`, `SheetChrome`, `StatusToggle`, `ProgressMeter`.

---

## Shared primitives

JIT-extracted by their first consumer.

### `NimbusError`

`Nimbus/Nimbus/State/NimbusError.swift`. Generalizes Phase 1's `BrowserError`.

```swift
struct NimbusError: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case authFailed
        case network
        case other
    }
    let kind: Kind
    let message: String

    /// Classifies a generic `Error` (typically from rclone or URLSession) into a
    /// typed kind. String-sniffs `localizedDescription` for common signals.
    /// Phase 2a heuristic; richer mapping to rclone codes can come in Phase 3.
    static func classify(_ error: Error) -> NimbusError
}
```

`BrowserViewModel.error` can either become a `typealias BrowserError = NimbusError` (backwards-compatible) or migrate outright. Cheap migration; decide during implementation.

`RemotesViewModel`, `MountsViewModel`, `TransfersViewModel` all migrate `error: String?` → `error: NimbusError?` and call `.classify(error)` on every `catch`.

### `FormSection`

`Nimbus/Nimbus/Components/FormSection.swift`. Wraps SwiftUI `Form { Section { ... }}` with consistent typography and a `LabeledContent`-style row API.

```swift
struct FormSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content
}

struct FormRow<Trailing: View>: View {
    let label: LocalizedStringKey
    let help: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing
}
```

Routes label / help text through `DesignSystem.Typography.body` / `.caption`. Help text appears in `textTertiary` under the row. Pattern: System Settings preference forms.

### `SheetChrome`

`Nimbus/Nimbus/Components/SheetChrome.swift`. Standard sheet layout shared across `AddRemoteSheet`, `EditRemoteSheet`, `ImportConfigSheet`, `AddMountSheet`, and retroactively `ConfirmCopySheet`.

```swift
struct SheetChrome<Body: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let body: () -> Body
    @ViewBuilder let actions: () -> Actions  // typically Cancel + primary action
}
```

Renders a top header (title + optional subtitle in `Typography.caption`), a scroll-host body with consistent `Spacing.xl` padding, and a bottom action bar with right-aligned buttons. Sheet radius from `DesignSystem.Radius.sheet` (14pt). Minimum width 460pt.

### `StatusToggle`

`Nimbus/Nimbus/Components/StatusToggle.swift`. Switch-style control for mount on/off with async-aware in-flight state.

```swift
enum StatusToggleState: Equatable, Sendable {
    case off
    case mounting       // transitioning off → on
    case on
    case unmounting     // transitioning on → off
    case error(reason: String)
}

struct StatusToggle: View {
    let state: StatusToggleState
    let onToggle: () -> Void  // async work fires on tap; caller updates state
}
```

`.off` / `.on` render the standard Switch look. `.mounting` / `.unmounting` overlay a tiny `ProgressView()` and disable tap until the transition resolves. `.error` renders a red-tinted indicator with hover tooltip. Caller manages the state machine; the view is pure presentation.

Implementation note: SwiftUI's `Toggle` doesn't natively support the in-flight `ProgressView` overlay. First attempt is SwiftUI-only. If the System-Settings-grade visual can't be matched, fall back to a tiny `NSViewRepresentable` wrapper around `NSSwitch` and a sibling overlay. Decision point during Mounts implementation.

### `ProgressMeter`

`Nimbus/Nimbus/Components/ProgressMeter.swift`. Linear progress bar variant of `StatusBadge`'s ring. Used in `TransferRow` where the ring is too small.

```swift
struct ProgressMeter: View {
    let progress: Double    // 0.0 ... 1.0
    let speed: Int64?       // bytes/sec, optional
    let eta: TimeInterval?  // remaining seconds, optional
}
```

Uses `DesignSystem.Color.semantic.statusWarning` (orange) for the bar fill — same color as `StatusBadge`'s downloading ring for visual continuity. Speed and ETA render in `Typography.caption` under the bar, dropped on narrow widths.

---

## Per-screen plans

### Remotes screen

**`RemotesView`** — main list, routed through `DesignSystem`.

- Empty state via `EmptyState`: icon `cloud.slash`, title "No Remotes Yet", message "Add a remote to start browsing cloud storage.", CTA "Add Remote" opens `AddRemoteSheet`.
- Cold-load: 3 skeleton `RemoteRow` placeholders with `.shimmering()`.
- Error: `NimbusError` rendered as a top banner.
  - `.authFailed`: "Some remotes need re-authentication" + "Reconnect All" affordance.
  - `.network`: existing daemon-down banner pattern, preserved.
  - `.other`: generic banner with retry.
- Toolbar: `+` (Add Remote), secondary `square.and.arrow.down` (Import Config), search field.

**`RemoteRow`** — Disk Utility's volume row as reference.

- Layout: provider icon (small mapping table per type), name in `Typography.body`, type subtitle in `Typography.caption` + `textTertiary`, status pill on right, chevron on hover.
- Status states (rendered via a small inline `StatusBadge`-style pill): `connected` (green), `auth-needed` (orange), `error` (red).
- Right-click menu: Browse / Edit / Import Config / Reconnect / Delete. Delete shows `.confirmationDialog` with destructive style.
- Drop target: accepts `NimbusFileBundle`, routes through `DragDropCoordinator` to copy to the remote root. Alternative wedge entry alongside Sidebar bookmarks.

**`AddRemoteSheet` + `ConfigForm` + `ProviderPicker`** — rebuilt around `SheetChrome` + `FormSection`.

- Two-step structure inside the same sheet (no second sheet):
  - **Step 1:** `ProviderPicker` — grid of provider tiles (icon + name) following the Apple "Add Account" grid pattern. Search filter on top. Click a provider → step 2.
  - **Step 2:** `ConfigForm` — `Form { FormSection { FormRow { ... }}}` populated from the chosen provider's parameter schema. Required fields show inline validation. Help text in `Typography.caption` under each row.
- Footer action bar (via `SheetChrome.actions`): Cancel (secondary) + Add Remote (primary, disabled until form valid). Back button visible in step 2 to return to provider picker.
- ProviderPicker grid tiles: 96×96 pt cards using `DesignSystem.Radius.card` and `Spacing.m` grid spacing, hover state tinted with `statusInfo.opacity(0.10)`.

**`EditRemoteSheet`** — same `SheetChrome` + `FormSection` pattern, pre-populated. Save / Cancel action bar. No provider picker (locked to existing type).

**`ImportConfigSheet`** — decomposed.

| File | Role | LOC target |
|------|------|------|
| `ImportConfigSheet.swift` | Orchestrator: file picker → state machine → action bar | ≤120 |
| `ImportPreviewList.swift` | Per-row include/exclude toggle list | ≤80 |
| `ImportConflictRow.swift` | Conflict resolution UI for name collisions | ≤60 |

Orchestrator owns the parsed config state and conflict policy. Preview list and conflict row are presentation-only. Empty state (no remotes parsed): `EmptyState` with icon `doc.text.magnifyingglass`.

### Mounts screen

**`MountsView`** — System Settings → Login Items as reference.

- Empty state via `EmptyState`: icon `externaldrive`, title "No Mounts Configured", message "Mount a remote to access it as a local volume.", CTA "Add Mount".
- Cold-load: 2 skeleton `MountRow` placeholders.
- Error: `NimbusError` banner.
- Toolbar: `+` Add Mount, secondary Refresh.

**`MountRow`** — Login Items row layout + inline inspector.

- Layout: mount-status-tinted icon (`externaldrive.fill` mounted, `externaldrive` not mounted, `externaldrive.badge.xmark` error), name + remote subtitle, trailing `StatusToggle`.
- Click anywhere on the row to expand `MountInspector` underneath (Disk Utility's volume detail pane pattern).
- Right-click menu: Reveal in Finder (mounted only) / Eject / Edit Mount / Delete.

**`MountInspector`** — expandable detail pane.

- Shown inline below the selected `MountRow`. Background `surfaceSubtle`, radius `Radius.card`.
- Rows: Mount point path (copyable), VFS mode (Off / Minimal / Writes / Full), Backend (NFS / FUSE), Last mounted (timestamp).
- Smooth expand/collapse via `DesignSystem.Motion.smooth`.

**`AddMountSheet`** — `SheetChrome` + `FormSection`. Remote picker (dropdown over existing remotes), mount-point folder picker (`fileImporter`), VFS mode picker, backend (NFS / FUSE) picker. Validation: mount point must be writable, remote must exist.

### Transfers screen

**`TransfersView`** — Mail outbox-while-sending as reference.

- Empty state via `EmptyState`: icon `arrow.up.arrow.down`, title "No Transfers", message "Cross-remote copies and syncs appear here.", no CTA.
- Two sections:
  - **Active** (top, grows) — currently running. Always visible.
  - **Recent** (collapsible, default expanded) — last 50 completed/failed.
- Section headers use `Typography.captionEmphasized`, like Mail's mailbox sections.
- Toolbar: Clear Completed (destructive style), filter by origin (`All / Cross-remote drops / Manual copies / Sync jobs`).

**`TransferRow`** — variant by status.

- **Active:** leading file icon, name + `qualifiedRemotePath` subtitle (truncated middle), trailing `ProgressMeter` with speed + ETA caption. Cancel button on hover.
- **Completed:** `● Done` green pill + completed-at timestamp.
- **Failed:** `! Error` red pill + truncated error message; hover for full message.
- Right-click menu: Cancel (active only), Show in Browser, Copy Error (failed only), Retry (failed only — re-issues the same DragDropCoordinator intent).

---

## Wedge

**Setup-to-mount in 60 seconds.** This is the Phase 2a ship gate, manually verified before merge.

End-to-end flow:

1. User opens Nimbus on the Remotes screen.
2. Clicks **+ Add Remote** in the toolbar.
3. `AddRemoteSheet` opens with the `ProviderPicker` grid. Picks a provider (e.g., S3 backed by a local folder for quick testing).
4. Step 2 shows the `ConfigForm`. User fills required fields. Help text + validation feel native.
5. Clicks **Add Remote**. Sheet dismisses. New `RemoteRow` appears in the list with `connected` status pill.
6. User clicks **Mounts** in the sidebar.
7. Clicks **+ Add Mount**, picks the new remote, picks a mount point, accepts defaults.
8. `AddMountSheet` dismisses. New `MountRow` appears with `StatusToggle` in `.off`.
9. User clicks the toggle. State transitions `.off → .mounting` (spinner overlay) → `.on` (filled blue).
10. Finder shows the mount in the sidebar under "Locations" within ~2 seconds.

Acceptance criteria: zero spinner anxiety, zero error toasts (in the happy path), zero janky sheet transitions, every step feels Apple-made.

---

## Testing strategy

TDD for logic; snapshot tests for components; manual + accessibility for screens.

### Unit tests (new primitives)

- `NimbusError`: classification helper for "auth" / "unauthorized" / "401" / "network" / "offline" / generic. Equatable round-trip. ~6 tests.
- `FormSection`: smoke-render test, accessibility-label propagation. ~2 tests.
- `SheetChrome`: render variants (no-footer, with-actions, with-subtitle). ~3 tests.
- `StatusToggle`: state-machine tests, tap-debounce during `.mounting`/`.unmounting`, accessibility-label includes state name. ~6 tests.
- `ProgressMeter`: snapshot tests at 0%, 50%, 100% via perceptual-hash infrastructure. ~3 tests.

### ViewModel migration tests

- `RemotesViewModel.error` migrated `String?` → `NimbusError?`: classify test for each kind. ~3 tests.
- `MountsViewModel.error` same. ~3 tests.
- `TransfersViewModel.error` same. ~3 tests.

### Snapshot tests for screen components

- `RemoteRow` snapshots per status state (connected / auth-needed / error). 3 fixtures.
- `MountRow` snapshots per `StatusToggle` state (off / mounting / on / error). 4 fixtures.
- `TransferRow` snapshots per status (active / completed / failed). 3 fixtures.

### Integration tests

One end-to-end ViewModel-level test per screen exercising empty → loading → loaded → error transitions via a stubbed `RcloneClient`. Same pattern as Phase 1's coordinator tests, not XCUITest.

### Manual gates before merge

- Setup-to-mount wedge demo (the ship gate).
- VoiceOver walkthrough of all three screens.
- Dynamic Type XXXL on the largest sheets (`ImportConfigSheet`, `AddRemoteSheet`).
- Side-by-side comparison vs Apple references:
  - Mounts vs System Settings → Login Items.
  - Transfers vs Mail outbox-while-sending.
  - AddRemoteSheet vs System Settings → Add Account.
- Build-time lints stay green; no new SPM deps; VoiceOver labels present on every interactive element in scope.

---

## Phase 1 carry-forward intersection

| Carry-forward | Phase 2a action | Reason |
|---------------|-----------------|--------|
| `BrowserError` → typed app-wide pattern | ✅ Generalized into `NimbusError` | Direct Phase 2a value. |
| Browser selection responsiveness | ❌ Not addressed | Browser-only; Phase 2a doesn't touch Browser. |
| AppKit `NSOutlineView` bridge | ❌ Not addressed | Same reasoning. |
| Real `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` | ❌ Not addressed | Only consumer is `CloudStatusColumn` in Browser. |
| `UTExportedTypeDeclarations` Info.plist | ❌ Not addressed | Wedge doesn't require OS-wide drag-drop. Phase 3 territory. |
| `NimbusUITests` target | ❌ Not addressed | Same XCUITest flakiness reasoning as Phase 1. |
| Cold folder-load latency | ❌ Not addressed | rclone-driven; not actionable at the app layer. |

---

## Exit gates

Phase 2a ships when **all** of:

### Objective

- All new primitive tests passing (`NimbusError`, `FormSection`, `SheetChrome`, `StatusToggle`, `ProgressMeter`).
- All new snapshot tests passing (`RemoteRow`, `MountRow`, `TransferRow`).
- All three ViewModel migrations have passing tests.
- Build-time lints green (zero `.system(size:)`, zero remote SPM deps).
- `Package.resolved` unchanged.
- VoiceOver: every interactive element in scope has a non-empty label.
- Dynamic Type XXXL doesn't break any in-scope layout.

### Subjective

- Two-minute walkthrough of each screen: zero non-native moments noted.
- Side-by-side comparisons cleared (Mounts vs Login Items; Transfers vs Mail outbox; AddRemoteSheet vs Add Account).
- All four design pillars hold for the three screens.

### Wedge

Setup-to-mount in ≤ 60 seconds, end-to-end smooth. Merge-blocker.

---

## Risks

- **`ImportConfigSheet` decomposition.** 282 LOC → three files. Migration is non-trivial; existing tests around config parsing must stay green. Budget 1–2 extra days.
- **`StatusToggle` async semantics.** SwiftUI `Toggle` doesn't natively support in-flight states. SwiftUI-first attempt; fall back to `NSViewRepresentable` over `NSSwitch` if the System-Settings-grade visual can't be matched. Decision point during Mounts implementation.
- **`TransferRow` width when ETA + speed + size all present.** Mail's outbox row drops some metadata at narrow widths; we mirror that.
- **Pattern extraction drift.** Earlier screens may need light refactor when a later screen forces a primitive to grow. Half-day budgeted per screen for retroactive cleanup.
- **`NimbusError` migration of Browser.** `BrowserError` is consumed in `BrowserView`'s error-state branch. Migration is mechanical but touches Browser, which is out of scope for Phase 2a. Choose at implementation time: keep `typealias BrowserError = NimbusError` (zero Browser changes) or migrate fully (cleaner; ~30 lines of Browser edits).

---

## Implementation order

Suggested ordering for the `writing-plans` phase to translate into TDD task-by-task plan:

| # | Task group | Days |
|---|-----------|------|
| 1 | `NimbusError` foundation + ViewModel migrations (Remotes, Mounts, Transfers) | 1 |
| 2 | `SheetChrome` + `FormSection` primitives with tests | 2 |
| 3 | Remotes: `RemotesView` + `RemoteRow` rebuild | 2 |
| 4 | Remotes: `AddRemoteSheet` + `ConfigForm` + `ProviderPicker` | 2–3 |
| 5 | Remotes: `EditRemoteSheet` | 1 |
| 6 | Remotes: `ImportConfigSheet` decomposition (3 files) | 2 |
| 7 | `StatusToggle` primitive with tests | 1–2 |
| 8 | Mounts: `MountsView` + `MountRow` + `MountInspector` | 2 |
| 9 | Mounts: `AddMountSheet` | 1 |
| 10 | `ProgressMeter` primitive with tests | 1 |
| 11 | Transfers: `TransfersView` + section grouping | 1–2 |
| 12 | Transfers: `TransferRow` (active / completed / failed variants) | 1–2 |
| 13 | Phase 2a exit verification + wedge smoke test | 1 |

**Rough total:** 18–22 working days.

---

## What's next

After this spec is reviewed and approved, `writing-plans` produces the task-by-task TDD implementation plan. Phase 2b (CopySync + Settings + Onboarding) gets its own brainstorm → spec → plan cycle once Phase 2a ships.
