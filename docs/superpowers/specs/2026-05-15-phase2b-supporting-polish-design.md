# Phase 2b: Supporting Screens Polish

**Date:** 2026-05-15
**Status:** Draft
**Parent:** [Nimbus North Star](./2026-05-14-nimbus-north-star-design.md)
**Predecessor:** [Phase 2a: Operational Polish](./2026-05-15-phase2a-operational-polish-design.md)
**Type:** Implementation design (second half of strategic Phase 2)
**Scope:** Apply the Phase 1/2a foundation across the three supporting screens (Onboarding, Settings, CopySync) with a deep HIG audit per screen. Add the `OnboardingCard` primitive JIT. Verify a first-launch-in-90-seconds wedge end-to-end before merge.

---

## Goals

1. **Three supporting screens cleared to HIG-grade.** Onboarding feels like macOS Setup Assistant. Settings feels like macOS Mail/Safari/Xcode Preferences. CopySync feels like a focused one-shot form sheet.
2. **One new primitive extracted JIT.** `OnboardingCard` with `.pending` / `.inProgress` / `.complete` / `.actionRequired` state machine.
3. **First-launch wedge works end-to-end** in under 90 seconds from a fresh install.
4. **All four design pillars hold** for the three screens at exit.

## Non-Goals

Explicitly **not** in Phase 2b:

- Any Phase 2a carry-forward: sticky error UX in Remotes/Mounts/Browser; `ConfigForm` Name-row duplication in `EditRemoteSheet`; live remote-status discovery; `MountManager.refreshAll()` real implementation. All defer to Phase 3 or a separate hardening pass.
- Browser-side Phase 1 carry-forwards (AppKit `NSOutlineView` bridge, real File Provider state lookups, UTI registration).
- Settings migration to the new System Settings sidebar pattern (TabView is correct for app Preferences per Apple's Mail/Safari/Xcode convention).
- New tests on existing primitives.
- Tier 2/3 features (encryption wizard, scheduled syncs, public links, media gallery).

---

## Architectural Decisions

Locked during the brainstorm session that produced this doc.

| Decision | Choice | Reason |
|----------|--------|--------|
| Phase 2b scope boundary | Strict — just Onboarding/Settings/CopySync | Carry-forwards balloon scope. Hardening pass or Phase 3 can absorb them. |
| Polish depth | Deep HIG audit per screen | Matches Phase 2a depth; user picked all four pain points. |
| Onboarding shape | Single-screen progressive cards | Matches macOS Setup Assistant; lowest friction; reveals as steps complete. |
| Order | Onboarding → Settings → CopySync | Wedge demo ships first, sets the bar. |
| Settings architecture | Keep TabView | Apple's Mail/Safari/Xcode pattern; sidebar Settings is System-only. |

---

## File structure changes

```
Nimbus/Nimbus/
├── Components/                                # additions
│   └── OnboardingCard.swift                   # NEW — state-machine card for Onboarding
├── Views/Onboarding/                          # REBUILT
│   └── OnboardingView.swift                   # progressive card stack
├── Views/Settings/                            # REBUILT (all sections)
│   ├── SettingsView.swift                     # tab order + window resize 520x360
│   ├── GeneralSection.swift
│   ├── AppearanceSection.swift
│   ├── TransferSection.swift
│   ├── RcloneSection.swift
│   ├── StorageUsageView.swift
│   └── AboutSection.swift
└── Views/CopySync/                            # REBUILT
    ├── CopySyncView.swift                     # FormSection + DestructiveCallout
    └── PathPicker.swift                       # rebuild against FormRow
```

Test additions: `Nimbus/NimbusTests/OnboardingCardTests.swift` with 4 snapshot fixtures.

No structural changes to other directories.

---

## Shared primitives

### `OnboardingCard`

`Nimbus/Nimbus/Components/OnboardingCard.swift`. State-machine card for the onboarding progressive flow.

```swift
enum OnboardingCardState: Equatable, Sendable {
    case pending          // Step not yet reachable
    case inProgress       // Step is working asynchronously (e.g. daemon starting)
    case complete         // Step succeeded; sub-CTA may surface next-step
    case actionRequired   // User must act (primary CTA visible)
}

struct OnboardingCard: View {
    let state: OnboardingCardState
    let icon: String              // SF Symbol name
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?  // sub-CTA shown only when state == .complete

    struct ActionConfig {
        let label: LocalizedStringKey
        let perform: () -> Void
    }
}
```

**Visual:**

- Card container: `RoundedRectangle(cornerRadius: Radius.card)` filled with `surfaceSubtle`, padding `Spacing.l`.
- Leading status indicator (24×24):
  - `.pending` → outline circle in `textTertiary`
  - `.inProgress` → `ProgressView()` controlSize `.small`
  - `.complete` → `checkmark.circle.fill` in `statusOK`
  - `.actionRequired` → filled circle in accent color
- Middle column (vertical):
  - Icon (SF Symbol, 32×32) tinted `statusInfo` for `.actionRequired`, `textSecondary` otherwise
  - Title in `Typography.headline`
  - Message in `Typography.body` + `textSecondary`
- Trailing primary action button:
  - `.actionRequired` → `.borderedProminent`
  - `.complete` with sub-CTA → plain link-style sub-CTA text below message ("Mount it for Finder →")
  - Other states → no button visible
- Smooth state transitions via `DesignSystem.Motion.smooth`.

**Accessibility:** `.accessibilityElement(children: .combine)` to merge label + state semantics; trait `.isButton` only when there's an action; per-state `.accessibilityValue` ("Pending", "In progress", "Complete", "Action required").

### `DestructiveCallout` (inline component, not promoted)

Lives at file scope inside `CopySyncView.swift`. Single consumer; promote to `Components/` only if Phase 3 needs it.

```swift
private struct DestructiveCallout: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.10))
        )
    }
}
```

---

## Per-screen plans

### Onboarding screen

Reference: macOS Setup Assistant — Apple's first-launch flow for system services like iCloud / Apple ID. Single-screen layout, cards reveal as their preconditions become true.

**`OnboardingView` rebuild:**

- Centered `VStack`, max width 560pt. Background `surface`.
- Hero section: SF Symbol `cloud` 64×64 in `statusInfo` + `Text("Welcome to Nimbus")` in `Typography.largeTitle.bold()` + subtitle "Your cloud storage, managed natively." in `Typography.title3` + `textSecondary`.
- Card stack (vertical, `Spacing.m` between):

  1. **Rclone Daemon** card — always visible. State map:
     - `daemon.status == .starting` or `.idle` → `.inProgress`
     - `daemon.status == .connected` → `.complete`
     - `daemon.status == .error(...)` → `.actionRequired` with primary CTA **Retry** (calls `daemon.retry(binaryPath:)`) and sub-CTA "Configure rclone path" that switches the user to the Settings tab opened to Rclone.

  2. **Add a Remote** card — revealed once daemon is `.connected` (use `if daemon.status == .connected && (always reveal)`):
     - No remotes → `.actionRequired` with primary CTA **Add Remote** that opens the Phase 2a `AddRemoteSheet`. On dismiss, list refreshes.
     - At least one remote → `.complete`. Message shows "Connected to <remote-name>". Sub-CTA: "Mount it for Finder →" that triggers card 3's action directly.

  3. **Mount Your Remote** card — revealed once at least one remote exists:
     - No mounts → `.actionRequired` with primary CTA **Add Mount** that opens the Phase 2a `AddMountSheet`. On dismiss, list refreshes.
     - At least one mount → `.complete`. Message shows "Mounted at <path>". Sub-CTA: "Browse it →" that triggers card 4's reveal and updates the Done button label.

  4. **You're all set** card — revealed once at least one mount exists. Single primary CTA: **Done** in `.borderedProminent` `.large`. Tapping sets `settings.onboardingComplete = true` which causes `ContentView` to dismiss `OnboardingView`.

- Card reveal: each card is wrapped in `if shouldShow(N)` so it materializes/dematerializes with `.transition(.opacity.combined(with: .move(edge: .top)))` animated by `DesignSystem.Motion.smooth`.
- State for tracking which sheets are open: `@State private var showingAddRemote: Bool`, `@State private var showingAddMount: Bool`.
- Data sources: `@Environment(RcloneDaemon.self)`, `@Environment(MountConfigStore.self)`, plus a small `@State private var remotes: [String]` refreshed via `daemon.client.listRemotes()` after dismissals.

**Failure modes:**

- Daemon error: card 1 stays `.actionRequired` indefinitely; Done is unreachable. Sub-CTA to Settings → Rclone covers the "rclone not installed / wrong path" case.
- AddRemoteSheet error: handled inside the sheet (Phase 2a); on dismiss Onboarding refreshes regardless. If no remote was actually added, card 2 stays `.actionRequired`.
- Same pattern for AddMountSheet.

### Settings screen

Reference: macOS Mail / Safari / Xcode Preferences. TabView with rounded section panes.

**`SettingsView`:**

- Window size: 520×360 (was 450×250). Allows FormSection rows to breathe.
- TabView order locked: General → Appearance → Transfers → Rclone → Storage → About.
- Padding around the TabView reduces; each pane provides its own internal `Spacing.xl` padding.

**Each `*Section`** follows the same rebuild template:

- Top-level container: `VStack(spacing: DesignSystem.Spacing.l)` with `.padding(DesignSystem.Spacing.xl)`.
- One or more `FormSection` blocks with `FormRow` rows.
- All `Toggle` and `Picker` use `.labelsHidden()` since labels live in `FormRow.label`.

**`GeneralSection`:**

- `FormSection(title: "Application", footer: nil)` with two `FormRow`s:
  - `FormRow(label: "Launch at Login", help: nil)` → `Toggle("", isOn: $launchAtLogin).toggleStyle(.switch)`
  - `FormRow(label: "Show in Menu Bar", help: nil)` → `Toggle(...)`

**`AppearanceSection`:**

- `FormSection(title: "Appearance", footer: nil)` with one `FormRow`:
  - `FormRow(label: "Color Scheme", help: nil)` → `Picker("", selection: $colorScheme)` with `.segmented` style, options Auto / Light / Dark.

**`TransferSection`:**

- `FormSection(title: "Transfers", footer: "Higher concurrency improves throughput but uses more memory.")`:
  - `FormRow(label: "Concurrent Transfers", help: nil)` → `Stepper("\(value)", value: $concurrentTransfers, in: 1...32)`
  - `FormRow(label: "Bandwidth Limit", help: "e.g. 1M, 10M, 100k, or empty for unlimited.")` → `TextField("Unlimited", text: $bandwidthLimit).frame(maxWidth: 160)`. Validation rejects invalid format on `.onChange`.

**`RcloneSection`:**

- `FormSection(title: "Binary", footer: nil)`:
  - `FormRow(label: "Path", help: nil)` → `Text(verbatim: settings.rcloneBinaryPath)` + `Button("Choose…")` opening `.fileImporter` for executable files.
  - `FormRow(label: "Version", help: nil)` → `Text(verbatim: daemon.rcloneVersion ?? "Unknown")`.
  - `FormRow(label: "", help: nil)` → `Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settings.rcloneBinaryPath)]) }`.
- `FormSection(title: "Daemon", footer: nil)`:
  - Status row showing connection state (uses the same status-pill pattern as RemoteRow but inline).
  - `FormRow(label: "", help: nil)` → `Button("Restart Daemon") { Task { await daemon.restart() } }`.

**`StorageUsageView`:**

- Standalone pane (not embedded in About).
- `FormSection(title: "Local Cache", footer: "Cached files speed up repeated access. Clearing removes only local copies — cloud files are unaffected.")`:
  - `FormRow(label: "Used", help: nil)` → ProgressMeter (Phase 2a) showing `usedBytes / totalCapacity` as a percentage. Caption shows `"X GB of Y GB"`. `usedBytes` comes from a best-effort `FileManager` walk of `~/Library/Caches/Nimbus/` (or wherever cache lives today — verify in implementation); if no cache directory exists yet, show 0 / "Empty".
  - `FormRow(label: "", help: nil)` → `Button("Clear Cache", role: .destructive)` triggers `.confirmationDialog` ("Remove all cached files? Cloud files are unaffected.") then performs the deletion via `try FileManager.default.removeItem(at:)` on the cache directory. After completion, recompute `usedBytes` (snaps to 0). Phase 2b ships with this real behavior; Phase 3 may extend to per-remote cache management.

**`AboutSection`:**

- Centered VStack (no FormSection — about pages are typically chrome-less).
- App icon (128×128), `Text("Nimbus")` in `Typography.largeTitle.bold()`, version + build in caption, copyright line.
- Footer: link "Powered by rclone" to https://rclone.org/.

### CopySync screen

Reference: Apple's one-shot form sheets (Safari "Save Page As", Pages "Export").

**`CopySyncView` rebuild:**

- Top: navigationTitle "Copy / Sync".
- Body: `VStack(spacing: DesignSystem.Spacing.l)` with two `FormSection`s:

  1. **Operation** — `FormSection(title: "Operation", footer: nil)`:
     - `FormRow(label: "Mode", help: nil)` → segmented `Picker` with Copy / Sync tags.
     - When `operation == .sync`: render a `DestructiveCallout(message: "Sync will make the destination identical to the source. Files in the destination not in the source will be deleted.")` below the picker, outside the FormSection (so the callout shape is clearly the warning, not a form row).

  2. **Paths** — `FormSection(title: "Paths", footer: nil)`:
     - Two `PathPicker` rows, labels "Source" / "Destination".

- Below the form: error display via inline `EmptyState(icon: "exclamationmark.triangle", title: "Couldn't start", messageVerbatim: error.message, action: .init(label: "Dismiss", perform: { error = nil }))` when `error != nil` AND no transfer is currently active.
- Bottom toolbar: trailing **Run** button in `.borderedProminent`. `.disabled(!isValid || isRunning)`. Label shows "Running…" with spinner overlay while a job is in-flight.

**`PathPicker` rebuild:**

- Rendered as `FormRow(label: label, help: nil)` with trailing content = HStack of:
  - Remote `Picker` (Choose… / available remotes) — frame width 140pt.
  - Path `TextField` with `prompt: "/"` — frame maxWidth 200pt.
- `selectedRemote` and `path` are `@Binding`s.
- Validation: path field disabled until a remote is selected.
- All typography / colors / spacing through `DesignSystem`.

`CopySyncViewModel` was migrated to `NimbusError?` in Phase 2a Task 1. View consumes `viewModel.error?.message` via the inline `EmptyState`.

---

## Wedge

**First-launch in 90 seconds.** Phase 2b ship gate, manually verified before merge.

End-to-end flow from `settings.onboardingComplete == false`:

1. User opens Nimbus → `ContentView` routes to `OnboardingView`.
2. Hero header visible; **Rclone Daemon** card in `.inProgress` (spinner).
3. Daemon transitions `.starting → .connected` within ~2s. Card transitions to `.complete`.
4. **Add a Remote** card reveals (animated) in `.actionRequired`. User taps **Add Remote**.
5. `AddRemoteSheet` (Phase 2a) opens. User picks a provider (e.g. `local` for a quick test), fills name + path, taps **Add Remote**. Sheet dismisses.
6. Onboarding refreshes. **Add a Remote** card transitions to `.complete` with "Connected to <name>" + sub-CTA "Mount it for Finder →".
7. **Mount Your Remote** card reveals (animated) in `.actionRequired`. User taps **Add Mount**.
8. `AddMountSheet` (Phase 2a) opens. User picks the new remote, picks a mount point, accepts defaults, taps **Add**. Sheet dismisses; mount toggle in MountsView triggers automatically on creation OR onboarding shows a follow-up to toggle it on. (Decision during implementation: simplest path is the AddMountSheet's `autoMount` default = true so the mount comes up on save.)
9. Onboarding refreshes. **Mount Your Remote** card transitions to `.complete` with "Mounted at <path>" + sub-CTA "Browse it →".
10. **You're all set** card reveals with **Done** button. User taps Done.
11. `settings.onboardingComplete = true`; ContentView swaps to the main app at the Remotes screen.

Acceptance: zero non-native moments, no spinner anxiety beyond the daemon-start step, no error toasts in the happy path, every step feels deliberate and Apple-made.

---

## Testing strategy

### Unit / snapshot tests (new primitive)

- `OnboardingCardTests`: 4 snapshot tests — one per state (`.pending`, `.inProgress`, `.complete`, `.actionRequired`). Uses the existing `SnapshotHelpers` perceptual-hash harness with `NIMBUS_SNAPSHOT_RECORD=1` to record fresh fixtures.

That's the only new test suite. Phase 2b's other surface (Onboarding flow, Settings sections, CopySync form) is screen-level and gets manual verification, same as the equivalent screens in Phase 2a.

### Manual gates before merge

- First-launch wedge demo (the ship gate).
- VoiceOver walkthrough of all three screens (Onboarding cards in particular — verify the state-pending/in-progress/complete semantics announce correctly).
- Dynamic Type XXXL on Settings sections + Onboarding cards. CopySync uses a fixed form layout that should scale gracefully.
- Side-by-side HIG comparisons:
  - **Onboarding** vs macOS Setup Assistant (iCloud / Apple ID setup).
  - **Settings** vs Apple Mail Preferences.
  - **CopySync** vs Pages "Export…" sheet.

---

## Phase 2a carry-forwards explicitly NOT addressed

These stay open into Phase 3 or a separate hardening pass:

- Sticky error UX in Remotes / Mounts / Browser views (silent post-first-load failures).
- `ConfigForm` Name-row duplication in `EditRemoteSheet`.
- Live remote-status discovery (RemoteRow's `.status` hardcoded to `.connected`).
- `MountManager.refreshAll()` real implementation (currently a no-op stub).

Phase 2b stays disciplined: only the three supporting screens get touched.

---

## Phase 2b exit gates

Phase 2b ships when **all** of:

### Objective

- Build green; both build-time lints pass.
- All 4 OnboardingCard snapshot tests pass.
- Full test suite passes — target **≥ 86 tests** (82 baseline + 4 OnboardingCard).
- `Package.resolved` unchanged.
- VoiceOver: every interactive element in scope has a non-empty label (manual gate).
- Dynamic Type XXXL doesn't break Settings sections or Onboarding cards (manual gate).

### Subjective

- Two-minute walkthrough of each screen: zero non-native moments noted.
- Side-by-side comparisons cleared (Onboarding vs Setup Assistant, Settings vs Mail Preferences, CopySync vs Pages Export).
- All four design pillars hold for the three screens.

### Wedge

- First-launch in ≤ 90 seconds, end-to-end smooth. Merge-blocker.

---

## Risks

- **`OnboardingCard` reveal animation jitter** when multiple cards transition simultaneously (e.g., a returning user with existing remotes & mounts triggers cards 2/3/4 to reveal all at once on first paint). Mitigation: each card individually animates its own state changes; the parent reveals via `if` + `.transition`, not a single-source animation block. Verify in the wedge demo.
- **Settings window-size jump** from 450×250 → 520×360. macOS preserves window position by autosave; the size change may make the window feel oddly placed on first open after update. Acceptable — one-time visual hiccup.
- **CopySync error-banner placement.** Inline above the Run button row, not below; keeps the form-action relationship visible.
- **First-launch wedge depends on a working rclone.** If rclone is missing or misconfigured, the daemon card stays in `.actionRequired` indefinitely. The Settings → Rclone sub-CTA covers this. Wedge can't complete without rclone; UX must communicate it clearly.

---

## Implementation order

Suggested ordering for the `writing-plans` phase to translate into TDD task-by-task plan:

| # | Task | Days |
|---|------|------|
| 1 | `OnboardingCard` primitive with 4 snapshot tests | 1.5 |
| 2 | Onboarding: rebuild `OnboardingView` with progressive card stack | 2 |
| 3 | Onboarding: wedge integration (AddRemoteSheet + AddMountSheet hookup, sub-CTAs, Done) | 1.5 |
| 4 | Settings: window resize + `SettingsView` shell | 0.5 |
| 5 | Settings: `GeneralSection` rebuild | 0.5 |
| 6 | Settings: `AppearanceSection` rebuild | 0.5 |
| 7 | Settings: `TransferSection` rebuild + validation | 0.5 |
| 8 | Settings: `RcloneSection` rebuild | 1 |
| 9 | Settings: `StorageUsageView` rebuild | 1 |
| 10 | Settings: `AboutSection` rebuild | 0.5 |
| 11 | CopySync: `CopySyncView` rebuild with FormSection + DestructiveCallout | 1.5 |
| 12 | CopySync: `PathPicker` rebuild against FormRow | 1 |
| 13 | Phase 2b exit verification + first-launch wedge demo | 1 |

**Rough total:** 11.5–13 working days. Smaller than Phase 2a (~18–22 days) — reflects the smaller LOC scope (~471 vs ~1561).

---

## What's next

After this spec is reviewed and approved, `writing-plans` produces the task-by-task TDD implementation plan. Phase 3 (System integration depth) brainstorm kicks off after Phase 2b ships.
