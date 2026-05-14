# Phase 1: Foundation + Browser

**Date:** 2026-05-14
**Status:** Draft
**Parent:** [Nimbus North Star](./2026-05-14-nimbus-north-star-design.md)
**Type:** Implementation design (Phase 1 of 5)
**Scope:** Build the foundation layer (design tokens, components, interaction primitives, perf harness) the Browser strictly needs, rebuild the Browser against it as a proving ground, sunset the Tauri app, and clear all four design pillars for the Browser screen.

---

## Goals

1. **Foundation layer exists** — design tokens, typography ramp, two components (`StatusBadge`, `EmptyState`), four interaction primitives (`Selection`, `DragDropCoordinator`, `QuickLookHost`, `KeyboardCoordinator`), perf harness (`BenchScene`).
2. **Browser is Finder-grade** — multi-select with Finder semantics, drag-and-drop in all three directions (within-remote, cross-remote, to/from Finder), Quick Look on every selectable item, type-to-select, keyboard shortcuts, sort/column behavior, contextual menus.
3. **Cross-remote drag works end-to-end** — the wedge moment: drag from Remote A → drop on Remote B → confirmation sheet → Copy job enqueued → progress ring on source row → swap to "● Local" pill on completion.
4. **Tauri app is sunset** — deprecation banner, frozen branch, source tree moved to `legacy/tauri/`, SwiftUI is the only documented and built primary.
5. **All four design pillars hold for Browser at exit** — native-or-nothing, Finder-grade interaction, utility-app rigor, performance is a feature (with numeric gates).

## Non-Goals

Explicitly **not** in Phase 1:

- Other screens — Remotes, Mounts, Transfers, CopySync, Settings, Onboarding remain at current state. They get the foundation treatment in Phase 2.
- Sidebar restructure. Today's NavigationSplitView pattern stays; sidebar polish is Phase 2.
- Encryption, scheduled syncs, public link sharing. Phase 4.
- Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish. Phase 3.
- Media gallery. Phase 5.
- Custom `QLPreviewItem` streaming from rclone. Explicitly rejected as Apple-fighting; system `QLPreviewPanel` + temp-download is the path.
- CI perf-regression hooks. `BenchScene` exists and passes manually for this phase; CI enforcement is Phase 1.5 or later.

---

## Architectural Decisions

Locked during the brainstorm session that produced this doc.

| Decision | Choice | Reason |
|----------|--------|--------|
| Browser tech stack | Hybrid: SwiftUI `Table` first, AppKit `NSOutlineView` via `NSViewRepresentable` if `Table` proves insufficient | Pragmatic. Foundation primitives are view-agnostic so the swap is local to `FileTable`. |
| Foundation scope | Browser-driven only — build only what Browser needs in Phase 1 | Solo dev capacity. Avoids speculative primitives built without real consumers. |
| Drag scope | All three (within-remote, cross-remote, to/from Finder) | Cross-remote is the wedge. Within and Finder are table stakes. |
| Quick Look | System `QLPreviewPanel` via `NSViewRepresentable` + temp-download for unmounted remotes | Most native path. Fighting Apple's URL-based architecture with custom `QLPreviewItem` is yak shaving. |
| Cross-remote drop UX | Confirmation sheet with conflict policy picker | Matches Finder when copying between volumes. Conservative — accidental drops don't fire transfers. |
| Cloud status indicator | Small pill (6pt radius, 10pt label) for stable states; Finder-style progress ring (icon only) for downloading state | Locked via visual companion v4. |

---

## File structure

```
Nimbus/Nimbus/
├── DesignSystem/                    # NEW
│   ├── Tokens/
│   │   ├── Colors.swift             # semantic color tokens via NSColor (Dark Mode / Increase Contrast aware)
│   │   ├── Spacing.swift            # 4pt scale: xs(4)/s(8)/m(12)/l(16)/xl(24)/xxl(32)
│   │   ├── Radius.swift             # 2/4/6/10/14 — pills 6, cards 10, sheets 14
│   │   └── Motion.swift             # Animation presets capped at 250ms
│   ├── Typography.swift             # semantic font helpers, zero .system(size:)
│   └── Lints.swift                  # #if DEBUG launch-time validators
├── Components/                       # NEW
│   ├── StatusBadge.swift            # cloud-status pill + progress ring
│   └── EmptyState.swift             # ContentUnavailableView wrapper with our typography + optional CTA
├── Interaction/                      # NEW (view-agnostic foundation)
│   ├── Selection.swift              # anchor + extended-set, Finder semantics
│   ├── DragDropCoordinator.swift    # DropIntent resolution, TransferStore integration
│   ├── QuickLookHost.swift          # QLPreviewPanel wrapper + MaterializationProvider
│   └── KeyboardCoordinator.swift    # KeyEquivalent registry + type-to-select buffer
├── Perf/                             # NEW
│   └── BenchScene.swift             # #if DEBUG hidden scene (⌥⌘B), scripted scenarios
└── Views/Browser/                    # REBUILT
    ├── BrowserView.swift            # composes foundation: toolbar + breadcrumb + table/grid + sheets
    ├── BrowserToolbar.swift         # update only — uses semantic tokens
    ├── FileTable.swift              # SwiftUI Table host wiring Selection + DragDrop + Keyboard + CloudStatusColumn
    ├── FileGrid.swift               # LazyVGrid using same primitives
    ├── FileContextMenu.swift        # update only
    ├── ConfirmCopySheet.swift       # NEW — cross-remote drop confirmation
    └── CloudStatusColumn.swift      # NEW — renders StatusBadge from TransferStore job state
```

Build script changes:

- `scripts/build-release.sh` — defaults to SwiftUI; Tauri target removed
- Tauri files relocate to `legacy/tauri/` (see [Tauri Sunset](#tauri-sunset))

---

## Foundation Layer

### Design tokens

Pure-Swift constants — zero magic numbers in views.

**Colors.** Semantic only. `DesignSystem.Color.semantic.accent`, `.surfaceSubtle`, `.statusOK`, `.statusWarning`, `.statusError`, `.statusInfo`, etc. All resolve through `NSColor` so they follow Dark Mode, Increase Contrast, and Reduce Transparency automatically. Direct hex/RGB calls are banned by `Lints.swift`.

**Spacing.** 4pt scale with named slots:

```swift
enum Spacing {
  static let xs: CGFloat = 4
  static let s:  CGFloat = 8
  static let m:  CGFloat = 12
  static let l:  CGFloat = 16
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
}
```

Views consume `DesignSystem.Spacing.m`, never numeric literals.

**Radius.** `2 / 4 / 6 / 10 / 14`. Pills use 6 (locked from visual companion), cards use 10, sheets use 14.

**Motion.** Three presets, all under 250ms:

```swift
enum Motion {
  static let snappy  = Animation.snappy(duration: 0.18)
  static let smooth  = Animation.smooth(duration: 0.22)
  static let springy = Animation.spring(.bouncy, duration: 0.25)
}
```

Animations longer than 250ms are a `Lints.swift` failure.

### Typography

`DesignSystem.Typography` exposes semantic font helpers (`.titleEmphasized`, `.body`, `.callout`, `.caption` — all backed by `Font.system(...)` semantic styles, never `.system(size:)`).

`.system(size:)` usage is forbidden and enforced at **build time** (see Lints).

### Lints

Two layers — build-time hard fail and runtime sanity check.

**Build-time** (a small Swift script invoked via an Xcode Run Script build phase that runs before compile):

- Greps Swift sources under `Nimbus/` and `RcloneKit/Sources/` for `\.system\(size:` regex — fails build with non-zero exit if any match
- Reads `Package.resolved`; fails if any dependency outside the allowlist (RcloneKit local package only) is present

**Runtime** (`DesignSystem/Lints.swift`, `#if DEBUG`-gated, runs at `NimbusApp.init`):

- Asserts core semantic color tokens resolve to non-nil `NSColor` in current appearance
- Verifies `BenchScene` menu item is wired (catches accidental removal)
- Logs a startup diagnostic line summarizing token counts for sanity

### Components

#### `StatusBadge`

```swift
enum CloudStatus: Equatable {
  case local
  case cloud
  case downloading(progress: Double)  // 0.0 ... 1.0
  case evicted
  case error(reason: String)
}

struct StatusBadge: View {
  let state: CloudStatus
  // Renders the visual locked in status-badge-v4 mockup:
  //   .local     → "● Local" green pill
  //   .cloud     → "☁︎ Cloud" gray pill
  //   .downloading → progress ring with centered down-arrow icon, no pill
  //   .evicted   → "⌀ Evicted" muted pill
  //   .error     → "! Error" red pill with reason in accessibility label
}
```

Accessibility: VoiceOver label says "Downloading 47 percent" for ring states, "Local" / "Cloud only" / "Evicted from local cache" / "Error: <reason>" for pill states.

#### `EmptyState`

```swift
struct EmptyState: View {
  let icon: String          // SF Symbol name
  let title: LocalizedStringKey
  let message: LocalizedStringKey?
  let action: ActionConfig?

  struct ActionConfig {
    let label: LocalizedStringKey
    let perform: () -> Void
  }
}
```

Wraps `ContentUnavailableView` with our typography + optional CTA button using `.borderedProminent` button style. Used for Browser's four empty cases (empty folder / loading / auth failed / offline) and as a reusable primitive for Phase 2.

### Interaction primitives

View-agnostic so the AppKit swap is local to `FileTable`.

#### `Selection<ID: Hashable>`

Anchor + extended-set selection model with Finder semantics.

```swift
@Observable
final class Selection<ID: Hashable> {
  private(set) var anchor: ID?
  private(set) var ids: Set<ID> = []

  func select(_ id: ID, in ordering: [ID])              // plain click: replace
  func extend(to id: ID, in ordering: [ID])             // shift-click: anchor → id
  func toggle(_ id: ID)                                 // ⌘-click: toggle membership
  func replace(with: Set<ID>)
  func clear()
}
```

Plugs into SwiftUI `Table`'s `Set<ID>` selection binding via a thin adapter.

#### `DragDropCoordinator`

```swift
enum DropIntent {
  case withinRemote(items: [FileItem], destPath: String)
  case crossRemote(items: [FileItem], sourceRemote: String, target: DropTarget)
  case toFinder(items: [FileItem])

  struct DropTarget { let remote: String; let path: String }
}

@MainActor
@Observable
final class DragDropCoordinator {
  let transferStore: TransferStore
  let rclone: RcloneClient

  func resolve(drop: [NimbusFileRef], onto target: DropTarget) -> DropIntent
  func apply(_ intent: DropIntent, conflictPolicy: ConflictPolicy) async throws
}
```

`NimbusFileRef` is a Codable `Transferable` payload `{ remoteName, path, size, isDir }`.

Within-remote drops apply immediately via `operations/movefile` (move) or `operations/copyfile` (⌥-modifier).
Cross-remote drops hand off to `ConfirmCopySheet`; on confirm, enqueue via `RcloneKit` and tag with a Nimbus UUID in `TransferStore`.
Finder drops use SwiftUI `Transferable` `URL` representations backed by the same temp-download path as `QuickLookHost`.

Drag image: stacked-icon group with count badge, built once on drag start (matches Finder convention).

#### `QuickLookHost`

`NSViewRepresentable` over `QLPreviewPanel`:

```swift
protocol MaterializationProvider {
  func resolveURL(for item: FileItem) async throws -> URL
}

final class FileProviderMaterializationProvider: MaterializationProvider {
  // For File-Provider-mounted remotes: returns the FP-domain URL,
  // calling NSFileProviderManager.requestDownloadForItem(...) if not yet materialized.
}

final class TempDownloadMaterializationProvider: MaterializationProvider {
  // For Nimbus-only browsed remotes: downloads via operations/copyfile to URL.temporaryDirectory.
  // Cleans up on QuickLookHost dismiss.
}

@MainActor
final class QuickLookHost: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  func show(items: [FileItem], provider: MaterializationProvider)
}
```

Provider selection: if the active remote is registered with `FileProviderBridge`, use `FileProviderMaterializationProvider`; else `TempDownloadMaterializationProvider`.

For multi-selection invocation, panel navigation (left/right arrows) traverses the selected set via QLPreviewPanel's standard navigation.

#### `KeyboardCoordinator`

```swift
@MainActor
@Observable
final class KeyboardCoordinator {
  func register(_ key: KeyEquivalent, modifiers: EventModifiers = [], scope: Scope, perform: @escaping () -> Void)
  func handle(event: NSEvent, scope: Scope) -> Bool
  func handleTypeToSelect(character: Character, against ids: [ID], onMatch: (ID) -> Void)
}
```

Type-to-select buffer: accumulates characters, resets after 0.5s of inactivity, prefix-matches against current row set using `String.localizedStandardCompare` (handles diacritics + non-ASCII correctly).

Browser registers:
- `space` → Quick Look
- `return` → open
- `delete` → trash
- `⌘D` → duplicate
- `⌘R` → rename
- `⌘I` → info
- `⌘N` → new folder
- arrow keys → selection navigation
- `⌘A` → select all

### Performance harness — `BenchScene`

`#if DEBUG` scene reachable via hidden menu item `⌥⌘B`. Scripted scenarios:

| Scenario | Measures | Target |
|----------|----------|--------|
| Cold launch timer | App-init to first-frame timestamp | ≤ 1.0s |
| 10k-item dir load | Synthetic 10k-entry remote → load-to-render | ≤ 200ms |
| Mount → Finder visible | `MountManager.mount` call → `NSFileProviderManager` visibility | ≤ 2.0s |
| Animation frames | Frame-time histogram during scripted scroll | No frame > 16ms in normal scroll |

Results dump to `~/Library/Application Support/Nimbus/bench/<timestamp>.json` so we can diff across builds. Phase 1 requires the harness to exist and pass once on M1 baseline; CI enforcement is Phase 1.5+.

---

## Browser Rebuild

### `BrowserView`

Thin composer:

1. Resolves a `BrowserViewModel` per remote (existing pattern)
2. Injects `Selection<String>`, `KeyboardCoordinator`, `QuickLookHost`, `DragDropCoordinator` as environment values
3. Renders breadcrumb + toolbar + content (`FileTable` or `FileGrid` per view mode)
4. Hosts confirmation sheets: `ConfirmCopySheet` (cross-remote), rename, new folder, delete

### `FileTable`

SwiftUI `Table` wrapped in a host view that:

- Binds table's `Set<String>` selection to the `Selection<String>` adapter
- Installs `KeyboardCoordinator` via `.focusable(true) + .onKeyPress` (or a small `NSEvent` monitor inside a tiny `NSViewRepresentable` if `.onKeyPress` proves limiting on macOS)
- Sets up drag sources via `.draggable` returning `NimbusFileRef` `Transferable` payload
- Sets up drop targets via `.dropDestination(for: NimbusFileRef.self)`
- Adds `CloudStatusColumn` subscribing to `TransferStore` jobs filtered by remote+path → `StatusBadge`

Columns: Status (CloudStatusColumn) | Name (icon + filename) | Size | Modified.

**AppKit escape hatch:** if `Table`'s drag image control proves insufficient (no Finder-style stacked drag image, weak drop highlight), replace its `Table` body with an `NSOutlineView`-backed `NSViewRepresentable`. All consumer code (Selection, KeyboardCoordinator, DragDropCoordinator wiring) remains identical because the primitives are view-agnostic. Decision point: during implementation order task 8 (FileTable rebuild), before task 9 starts — once we've actually attempted drag image control on SwiftUI `Table`.

### `FileGrid`

`LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DesignSystem.Spacing.m)])` with same selection / drag / keyboard / quicklook bindings. Rendering differs only in tile vs row.

### `BrowserToolbar`

Existing toolbar updated to use semantic tokens + new components. No structural change; sidebar restructure is Phase 2.

### `ConfirmCopySheet`

Cross-remote drop confirmation:

```
┌─────────────────────────────────────────┐
│  Copy 3 items?                          │
├─────────────────────────────────────────┤
│  Source:  gdrive:/Photos                │
│  Target:  s3-backup:/2026/backups       │
│                                         │
│  3 items · 1.2 GB                       │
│   • IMG_4827.heic (2.1 MB)              │
│   • IMG_4828.heic (2.4 MB)              │
│   • IMG_4829.heic (2.0 MB)              │
│                                         │
│  If a file exists:                      │
│    ◉ Rename  ○ Skip  ○ Overwrite        │
│                                         │
│              [ Cancel ]  [ Copy ]       │
└─────────────────────────────────────────┘
```

Driven by `@State` `CopyRequest?` and presented via `.sheet(item:)`. On Copy, enqueues via `DragDropCoordinator.apply(_:conflictPolicy:)`.

### `CloudStatusColumn`

Subscribes to `TransferStore.activeJobs` filtered by `(remote: currentRemote, prefix: currentPath)`. Maps each row's path to:

- No matching active job + materialized in FP cache → `.local`
- No matching active job + not materialized → `.cloud` (or `.evicted` if recently evicted; FP API distinguishes)
- Matching active job → `.downloading(progress: job.progress)`
- Most recent job failed → `.error(reason: job.lastError)`

Progress updates via `TransferStore`'s `@Observable` notification at ~10fps to avoid layout thrash.

---

## Cross-Remote Drag Flow (Wedge)

End-to-end:

1. **Drag start.** User selects N rows in Remote A's `FileTable`. Drag initiates via `.draggable { NimbusFileRef(remoteName: A, path: row.path, ...) }`. Drag image: Finder-style stacked icons with count badge.
2. **Drop target.** Sidebar rows and `BrowserView` register `.dropDestination(for: NimbusFileRef.self) { items, location in coordinator.resolve(drop: items, onto: ...) }`.
3. **Coordinator resolution.** `DragDropCoordinator.resolve` inspects refs vs target. If `sourceRemote == target.remote` → `.withinRemote`; else `.crossRemote`.
4. **Within-remote path.** `apply(.withinRemote)` directly fires `operations/movefile` (or `operations/copyfile` with ⌥-modifier). No sheet.
5. **Cross-remote path.** `apply(.crossRemote)` sets a `@State CopyRequest?` on `BrowserView`, which presents `ConfirmCopySheet`. On Copy:
   - Enqueue via `RcloneKit`: 1 `sync/copy` job per item if N ≤ 5, else a single `sync/copy` directive covering all items
   - Register each job with `TransferStore`, tag with Nimbus-generated UUID + `origin: .crossRemoteDrop`
6. **Progress.** `CloudStatusColumn` shows `.downloading(progress:)` on source rows that have an active job. `TransferStore` drives the Transfers view as today.
7. **Completion.** `TransferStore` marks job complete → source row swaps to `.local` pill → toast notification (system notification if window not focused).

### Conflict handling

`ConfirmCopySheet`'s conflict policy maps to rclone flags:

| Policy | rclone behavior |
|--------|-----------------|
| Rename | `--suffix _conflict-<timestamp>` + `--backup-dir` not used; rclone renames on collision |
| Skip | `--ignore-existing` |
| Overwrite | (default rclone behavior) |

---

## Quick Look Flow

1. User presses Space (or chooses Quick Look from context menu)
2. `KeyboardCoordinator` dispatches `QuickLookHost.show(items: selection.items, provider: providerForCurrentRemote())`
3. `QuickLookHost` resolves URLs:
   - **FP-mounted remote**: `FileProviderMaterializationProvider` returns the FP-domain URL, calling `NSFileProviderManager.requestDownloadForItem(...)` if not materialized; system shows panel loading state
   - **Nimbus-only browsed remote**: `TempDownloadMaterializationProvider` downloads to `URL.temporaryDirectory` via `operations/copyfile` to a local rclone remote
4. Presents `QLPreviewPanel`; arrow keys navigate within selection
5. On dismissal, temp files from step 3 (non-FP path only) deleted

Multi-GB files: surface download progress within the panel's loading state. Dismissing the panel cancels the underlying job.

---

## Empty / Loading / Error States

Four `EmptyState` consumers in Browser:

| State | Icon | Title | Message | CTA |
|-------|------|-------|---------|-----|
| Empty folder | `folder` | "Empty Folder" | "Drop files here or use ⌘N to create a folder." | "New Folder" |
| Auth failed | `key.slash` | "Sign In Required" | "<remote name>: <reason>" | "Reconnect Remote" → jumps to Remotes view |
| Offline | `wifi.slash` | "Can't Reach Cloud" | "<underlying error>" | "Retry" |
| Loading | — | — | — | Skeleton rows in `FileTable` (8 stub rows, `.redacted(reason: .placeholder)` + shimmer modifier); pure spinner only when nothing in cache |

---

## Tauri Sunset

Executed at the start of Phase 1, in three commits:

### Commit 1 — Mark deprecated

- Add `DEPRECATED.md` at repo root pointing at the SwiftUI app
- Add About-dialog banner in the Tauri app: "Nimbus is moving to native Swift. This build is end-of-life."
- Bump Tauri version suffix to `-eol`

### Commit 2 — Freeze branch

- Cut `tauri-eol` branch from `main` at the current commit
- Update `CLAUDE.md` to remove dual-track guidance (single-app project from now on)

### Commit 3 — Relocate

Move to `legacy/tauri/`:
- `src/`
- `src-tauri/`
- `package.json`, `package-lock.json`
- `vite.config.ts`, `tsconfig*.json`
- `biome.json`
- `index.html`, `components.json`, `public/`

Update:
- `scripts/build-release.sh` → targets SwiftUI by default; Tauri build path removed
- `README.md` → SwiftUI is the documented primary; Tauri appears only as a "legacy archive" footnote
- `2026-03-31-swift-swiftui-rewrite-design.md` and `2026-03-31-swift-swiftui-rewrite.md` → move to `docs/superpowers/specs/` and `docs/superpowers/plans/` respectively (they're the original SwiftUI design docs sitting in repo root)

Deletion of `legacy/tauri/` happens later (~end of Phase 2 or Phase 3) once SwiftUI fully replaces it for shipped users.

---

## Testing Strategy

TDD applies to logic, not view bodies.

### Foundation primitives — high coverage

- `Selection<ID>` — anchor behavior, shift-extend, ⌘-toggle, replace, clear, edge cases (empty/single/range across reordered list). Target: 100% line coverage.
- `DragDropCoordinator` — `DropIntent` resolution per drop kind; mock `TransferStore`; verify correct enqueue payloads (single-item `operations/copyfile` vs batched `sync/copy` chunking at N>5).
- `KeyboardCoordinator` — registry lookup; type-to-select buffer with injected clock for 0.5s timeout; diacritics/non-ASCII prefix matching.
- `QuickLookHost.MaterializationProvider` selection — given remote-state input, asserts correct provider chosen.

### Components — snapshot + accessibility

- `StatusBadge` — XCTest snapshot per state × {light, dark, increase contrast}. VoiceOver label test for downloading-with-progress.
- `EmptyState` — snapshot per configured permutation.

### Browser — integration (one critical test)

- End-to-end wedge UI test: boot app with fake `RcloneDaemon` (in-memory `RcloneClient` stub), seed two fake remotes with files, drag from one to the other, accept `ConfirmCopySheet`, assert a `sync/copy` request lands in the stub and `TransferStore` receives a job with `origin: .crossRemoteDrop`.

### Accessibility audit script

Walks every Browser interactive element at test time, asserts non-empty `accessibilityLabel`.

### Performance

`BenchScene` scenarios must pass on M1 baseline manually before phase exit. Results JSON dumped to `~/Library/Application Support/Nimbus/bench/`. No CI hook in Phase 1.

---

## Phase 1 Exit Gates

Phase 1 ships when **all** of:

### Objective

- Cold launch ≤ 1.0s on M1 baseline (manual `BenchScene` run)
- 10k-item dir cold load ≤ 200ms
- Mount → Finder-visible ≤ 2.0s
- All foundation-primitive unit tests passing
- `StatusBadge` snapshot tests passing (light/dark/contrast)
- Cross-remote drag end-to-end UI test passing
- `Lints.swift` reports zero `.system(size:)` calls
- `Package.resolved` shows zero UI dependencies (RcloneKit local package only)
- VoiceOver audit: every Browser interactive element labeled
- Dynamic Type XXXL doesn't break Browser layout (manual)

### Subjective

- Two-minute Browser walkthrough: zero non-native moments noted
- Side-by-side with Finder for list-view interactions (type-to-select, drag, multi-select, Quick Look, keyboard shortcuts, contextual menu): any Finder behavior in scope that Nimbus doesn't match goes on the must-fix list before exit
- Tauri tree successfully relocated to `legacy/tauri/`; SwiftUI is the only build target

### Wedge

The single demo-able flow that defines Phase 1 success:

> Drag 3 files from Remote A's Browser → drop on Remote B's sidebar entry → confirmation sheet appears with source/target/items/conflict-policy → Copy → transfers appear in Transfers view, source rows show progress ring → complete → rows swap to "● Local" pill.

This flow must be smooth, native-feeling, and Finder-grade end-to-end.

---

## Risks

- **SwiftUI `Table` drag image control may be insufficient.** Budget for an `NSViewRepresentable` proof-of-concept around `NSTableView` if the stock drag image looks wrong. Decision point: during task 8 (FileTable rebuild), before task 9 starts.
- **Cross-remote `sync/copy` job tagging.** rclone's RC API doesn't tag jobs with caller-supplied metadata. Wrap each job with a Nimbus-generated UUID tracked in `TransferStore` separately. Don't pretend rclone tracks origin semantically.
- **Type-to-select with diacritics / non-ASCII filenames.** Use `String.localizedStandardCompare` for prefix matching. Add a test for `é`, `ñ`, `日` prefixes specifically.
- **Quick Look on multi-GB files.** Temp-download path will block previewing on a 4GB mov. Surface download progress in the QLPreviewPanel-loading state; cancel via panel dismiss.
- **`.onKeyPress` limitations on macOS.** If SwiftUI's `.onKeyPress` proves insufficient (no key-up events, no modifier-only events), drop to an `NSEvent` monitor inside a tiny `NSViewRepresentable`. Foreseeable; not a blocker.
- **Polish-first momentum cost.** Phase 1 alone is ~25-28 working days with no new user-visible feature. Bake the cost into expectations.

---

## Implementation Order

Suggested ordering for the writing-plans phase to translate into TDD task-by-task plan:

| # | Task | Days |
|---|------|------|
| 1 | Tauri sunset (3 commits) | 1 |
| 2 | DesignSystem/Tokens + Typography + Lints | 1-2 |
| 3 | Components/EmptyState + StatusBadge (with snapshot tests) | 2 |
| 4 | Interaction/Selection model (TDD) | 1 |
| 5 | Interaction/KeyboardCoordinator + type-to-select (TDD) | 2 |
| 6 | Interaction/QuickLookHost | 3 |
| 7 | Interaction/DragDropCoordinator (TDD) | 3 |
| 8 | Browser/FileTable + FileGrid against foundation | 3 |
| 9 | Browser/ConfirmCopySheet + cross-remote wiring + TransferStore tagging | 3 |
| 10 | Browser/CloudStatusColumn + TransferStore progress binding | 1-2 |
| 11 | Browser empty/error/loading states + skeleton rows | 1 |
| 12 | Perf/BenchScene + scenarios | 2 |
| 13 | Phase exit verification + cleanup | 2 |

**Rough total:** 25-28 working days. Strategic doc's 3-4 week estimate lands at upper end.

---

## What's next

After this spec is reviewed and approved, the writing-plans skill turns the implementation order into a task-by-task TDD plan with checkbox tracking. That plan is what an agent (or you) executes to ship Phase 1.
