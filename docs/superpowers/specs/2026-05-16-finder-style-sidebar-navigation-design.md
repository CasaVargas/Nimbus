# Finder-Style Sidebar Navigation — Design

**Date:** 2026-05-16
**Status:** Approved (pending spec review)
**Area:** SwiftUI app navigation (`Nimbus/Nimbus/`)

## Problem

When the user browses a remote, the toolbar shows **two visually identical
back chevrons** that do completely different things:

1. `‹` — SwiftUI's auto-generated `NavigationStack` back button, returning to
   the standalone Remotes list page.
2. `‹ ›` — `BrowserToolbar`'s explicit folder back/forward (folder history
   within the remote).

Root cause: `ContentView` has a single "Remotes" sidebar item whose detail is
`RemotesView` (a list of remote cards). Clicking **Browse** pushes a
`BrowserDestination` onto a `NavigationStack`, and that push generates the
implicit back chevron. Two unrelated "back" affordances sit side by side and
are indistinguishable.

## Goal

Adopt the macOS-native model (Finder Locations): the sidebar **is** the list
of remotes. Selecting a remote shows its browser directly in the detail pane.
No navigation push, therefore no auto-back chevron — the only back/forward in
the toolbar is folder history.

## Non-Goals

- No change to folder-history behavior, the breadcrumb path bar, or
  `BrowserViewModel`.
- No change to Mounts / Transfers / Copy-Sync views or their toolbars.
- No remote-list search (dropped — see Decisions).
- No change to onboarding, daemon lifecycle, or the File Provider extension.

## Architecture

```
NavigationSplitView
├── Sidebar
│   ├── RemotesSidebarSection   ← owns RemotesViewModel + status probing,
│   │   ├── SidebarRemoteRow…       hosts Add/Import/Edit/Delete sheets
│   ├── Mounts / Transfers / Copy-Sync rows
│   └── Bookmarks section (unchanged structure)
└── detail (switch on SidebarSelection)
    ├── .remote(name) → BrowserView(remoteName:).id(name)
    ├── .mounts       → MountsView
    ├── .transfers    → TransfersView
    └── .copySync     → CopySyncView
```

The `NavigationStack` and `NavigationPath` in `ContentView` are **removed
entirely**. `BrowserDestination` is removed. None of the detail views ever
pushed, so nothing is lost.

## Components

### `SidebarSelection` (new)

Replaces `SidebarItem` as the sidebar's selection value:

```swift
enum SidebarSelection: Hashable {
    case remote(String)
    case mounts
    case transfers
    case copySync
}
```

`ContentView` holds `@State private var selection: SidebarSelection?`.

### `SidebarRemoteRow` (new)

Slim sidebar row, distinct from the retired list-oriented `RemoteRow`:

- `ProviderIcon(provider: remote.type, size: 18)`
- Remote name (`DesignSystem.Typography.body`)
- Trailing small status dot driven by `RemoteStatus.tintColor`
  (a filled circle, not the full pill — the pill is too heavy for a sidebar
  row). `accessibilityLabel` = `status.accessibilityLabel`.
- Context menu: **Browse**, **Edit…**, **Reconnect** (only when
  `status == .authNeeded`), divider, **Delete…** (destructive) — the same
  action set `RemoteRow` exposed.
- `#Preview` covering connected / auth-needed / unknown states.

`RemoteRow.swift` and `RemotesView.swift` are deleted. `RemoteStatus` (the
enum) currently lives in `RemoteRow.swift`; it moves to its own file
`Views/Remotes/RemoteStatus.swift` so it survives the deletion.

### `RemotesSidebarSection` (new)

Container view rendered inside `Sidebar`. Responsibilities:

- Owns `@State private var viewModel: RemotesViewModel?`, created when
  `daemon.status == .connected` (mirrors today's `RemotesView.task`).
- On load: `await viewModel.loadRemotes()` then
  `statusService.probeAll(names)` — this side effect moves here from
  `RemotesView` so status dots stay live without the standalone page.
- Renders the `REMOTES` section: header with a trailing **"+" menu**
  (`Menu` → *Add Remote…* / *Import Config…*), then one `SidebarRemoteRow`
  per remote, tagged `.remote(name)`.
- Hosts the sheets previously in `RemotesView`: `AddRemoteSheet`,
  `ImportConfigSheet`, `EditRemoteSheet`, and the delete `confirmationDialog`.
  Each `onDismiss` re-runs `loadRemotes()`.
- States:
  - daemon not connected → no remote rows (header still shows, "+" disabled,
    matching today's `.disabled(daemon.status != .connected)`).
  - connected & empty → inline "Add Remote" affordance under the header.

### Detail pane

`ContentView.detailView` switches on `SidebarSelection`:

- `.remote(name)` → `BrowserView(remoteName: name).id(name)`
- `.mounts` / `.transfers` / `.copySync` → unchanged views.
- `nil` → `EmptyState` prompting to select or add a remote.

`BrowserView`'s `initialPath` parameter is retained for the `BrowseTarget`
flow below.

### `BrowseTarget` (new) — open a specific path

Bookmarks and the `openBrowser` environment action must still open a remote at
a specific path without a navigation push.

```swift
struct BrowseTarget: Equatable { let remote: String; let path: String }
```

- `ContentView` holds `@State private var browseTarget: BrowseTarget?`.
- Triggering it sets `selection = .remote(remote)` **and**
  `browseTarget = BrowseTarget(remote, path)`.
- `BrowserView` observes the target via `.onChange(of:)`: when the target's
  remote matches its own, it calls `viewModel.navigateTo(path:)`. This
  preserves the live browser instead of recreating it (so a bookmark jump
  inside the already-open remote works).
- On first appearance, `BrowserView` consumes a matching pending target as its
  initial path.

`OpenBrowserAction` and the `\.openBrowser` environment key are kept but their
closure now sets `selection` + `browseTarget` instead of appending to a path.

## Data Flow

1. App launch → `ContentView` selection defaults to `nil`; once remotes load,
   auto-select the first remote (`selection = .remote(firstName)`), else show
   the empty state.
2. User clicks a remote in the sidebar → `selection = .remote(name)` → detail
   renders `BrowserView` keyed by name → `BrowserViewModel` loads root.
3. User navigates folders → handled entirely by `BrowserViewModel` history +
   breadcrumb + `BrowserToolbar` back/forward (unchanged). No second chevron.
4. User clicks a bookmark → `selection = .remote(remote)` +
   `browseTarget = (remote, path)` → `BrowserView` navigates to `path`.
5. User picks **Add / Import / Edit / Delete** → sheet/dialog in
   `RemotesSidebarSection` → on dismiss, `loadRemotes()` refreshes the list.

## Edge Cases

- **Deleting the selected remote:** after delete, recompute selection via a
  small pure helper `nextSelection(after:deleted:in:)` →
  first remaining remote, or `nil`. Helper is standalone and unit-tested.
- **Zero remotes:** sidebar shows inline Add affordance; detail shows
  `EmptyState(icon: "cloud.slash", title: "No Remotes Yet", …)` reusing the
  existing copy from `RemotesView`.
- **Daemon error / starting:** detail pane keeps the existing daemon-status
  handling currently in `RemotesView.content` (idle/starting spinner, error
  `EmptyState` with Retry). This logic moves into the detail's no-/remote
  branch so it isn't lost with `RemotesView`.
- **Auth-needed remote selected:** browser still opens; existing
  `BrowserViewModel` error handling surfaces the auth error. Reconnect remains
  available from the row context menu.
- **Re-selecting the already-selected remote:** no-op (SwiftUI selection
  binding doesn't re-fire); `.id(name)` keeps the live browser.

## Testing

- **Unit:** `nextSelection(after:deleted:in:)` selection-fallback logic in a
  new `Nimbus/NimbusTests/SidebarSelectionTests.swift`
  (selected-deleted, non-selected-deleted, last-remote-deleted).
- **Unit:** existing `RemotesViewModel` load/delete coverage retained;
  no behavior change to the view model itself.
- **Test cleanup:** `Nimbus/NimbusTests/RemoteRowTests.swift` is removed (its
  subject `RemoteRow` is deleted); any reusable assertions migrate to a
  `SidebarRemoteRow` preview/test.
- **Visual:** `#Preview` for `SidebarRemoteRow` (connected / authNeeded /
  unknown). Verify the full sidebar + browser via RenderPreview per the
  project UI workflow — confirm exactly one back/forward control and no
  duplicate chevron.
- **Build:** XcodeBuildMCP `build_macos` (Debug) green; `xcodegen generate`
  re-run after adding/removing source files.

## Decisions / Rationale

- **Remove `NavigationStack` rather than reposition buttons:** the duplicate
  chevron is *inherent* to pushing the browser as a destination. Removing the
  push is the only fix that eliminates it without fighting SwiftUI.
- **Drop remote-list search:** a sidebar list of a handful of remotes does not
  warrant a search field (YAGNI). Re-add later only if a user actually has
  enough remotes to need it.
- **Slim status dot, not the pill:** the full `RemoteStatus` pill is designed
  for an inset list row and is visually too heavy for a sidebar row.
- **`BrowseTarget` observed by the live browser** (vs. re-keying `BrowserView`
  per path): preserves folder history when jumping via a bookmark inside the
  current remote.

## Affected / New Files

| Action | File |
|--------|------|
| Modify | `Nimbus/Nimbus/Views/ContentView.swift` (remove NavigationStack/Path, new selection, BrowseTarget, detail switch) |
| Modify | `Nimbus/Nimbus/Views/Sidebar.swift` (new `SidebarSelection`, embed `RemotesSidebarSection`, bookmark → selection+target) |
| New | `Nimbus/Nimbus/Views/Remotes/RemotesSidebarSection.swift` |
| New | `Nimbus/Nimbus/Views/Remotes/SidebarRemoteRow.swift` |
| New | `Nimbus/Nimbus/Views/Remotes/RemoteStatus.swift` (extracted from RemoteRow) |
| Modify | `Nimbus/Nimbus/Views/Browser/BrowserView.swift` (consume `BrowseTarget`) |
| Delete | `Nimbus/Nimbus/Views/Remotes/RemotesView.swift` |
| Delete | `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift` |
| New | `Nimbus/NimbusTests/SidebarSelectionTests.swift` (selection-fallback helper unit test) |
| Delete | `Nimbus/NimbusTests/RemoteRowTests.swift` (subject removed) |
| Run | `cd Nimbus && xcodegen generate` after file add/remove |
