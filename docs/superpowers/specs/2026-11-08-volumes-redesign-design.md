# Volumes Redesign — Design

**Date:** 2026-11-08
**Status:** Implemented 2026-11-08 (user chose "Direction 2: Volumes, borrowing from Direction 1" from the
mockup review page)
**Supersedes:** the Library/Finder/Transfers/Copy & Sync sidebar layout from the Phase 1–2
specs. Browser internals (table, grid, selection, drag, Quick Look) are unchanged.

## Why

Nimbus today is a Finder-shaped browser with three unrelated utility panes bolted to the
sidebar (Finder, Transfers, Copy & Sync). A remote's most important facts, how full it is,
whether it is in Finder, and what is moving right now, are spread across four screens. The
north star says Finder plus Disk Utility; this design makes the Disk Utility half real:
**a remote is a volume**, and selecting it shows everything about that volume in one pane.

## Goals

1. One pane per remote with the header, gauge, verbs, and tabs from the mockup.
2. Mount-in-Finder is a verb on the volume, not a separate screen.
3. Transfers are visible while they run (bottom drawer and toolbar pill) and have a
   per-volume history tab.
4. A file inspector replaces the per-row status pill as the place for cloud-status detail.
5. Nothing that works today stops working: NFS mounts, File Provider domains, copy/sync,
   bookmarks, Quick Look, drag between remotes, Settings window.

## Non-goals

- Scheduled sync jobs. The mockup's "Nightly" label is future work; v1 has no scheduler.
- Per-category storage breakdown (Photos / Documents / Other). Requires walking the tree;
  v1 shows used vs. free only.
- Light/dark or token changes. Everything uses existing `DesignSystem` tokens.
- Changing the File Provider extension.

## The window

```
┌──────────────┬──────────────────────────────────────────────────────────────┐
│ ○ ○ ○        │ [Volume name]                     [Add Volume]  [⚙]  [▣ Insp] │
├──────────────┼──────────────────────────────────────────────────────────────┤
│ Volumes      │  ◯ Personal Drive                 [Open in Finder] [Sync…]   │
│  ◉ Personal  │    Google Drive · 1.28 TB of 2 TB · Shown in Finder  [Edit]  │
│    ▬▬▬▬▬▬░░  │  ████████████████████░░░░░░░░░░  used 1.28 TB · free 720 GB  │
│  ◉ Backups   │  Files   Transfers   Finder   Settings                       │
│    ▬▬░░░░░░  │  ─────────────────────────────────────────────┬──────────── │
│  ◉ OneDrive  │  Name ⌃            Date Modified       Size   │ Inspector   │
│    ▬▬▬▬▬▬▬▬  │  ▸ Documents       Today            380 GB   │  (optional) │
│              │  ▸ Photos          Today            680 GB   │             │
│ Tools        │  ☁ Budget.xlsx     Oct 21          840 KB   │             │
│  Copy & Sync │                                               │             │
│              ├───────────────────────────────────────────────┴──────────── │
│ ● connected  │ ⇅ Transfers · 2 active · 14 MB/s                        ▾   │
│              │  ↑ 2026 Yosemite → Backups        ▬▬▬▬▬▬▬░░░  4 min          │
└──────────────┴──────────────────────────────────────────────────────────────┘
```

### Sidebar

- **Volumes** section: one row per remote. Provider icon, name, status dot (unchanged),
  plus a 3 pt capacity bar under the row when the remote reports a quota. No bar when
  `about` returns no `total` (S3, SFTP, local). The bar tint is the accent; above 90% it
  is `statusWarning`.
- **Tools** section: Copy & Sync only. Transfers and Finder leave the sidebar.
- Bookmarks section unchanged. Status bar at the bottom unchanged.
- The section header's `+` menu keeps Add Remote / Import Config.

### Volume pane (`VolumeView`)

Replaces `BrowserView` as the detail view for `.remote(name)`. Composition, top to bottom:

1. **Header.** `ProviderIcon` at 44 pt, remote name as title, subtitle
   `"<provider description> · <used> of <total> · Shown in Finder"` (segments drop out when
   unknown). Trailing verbs:
   - Primary: **Open in Finder** when a File Provider domain is active for this remote,
     else **Show in Finder** (registers the domain; same code path as the Finder pane's
     toggle today).
   - **Sync…** selects Copy & Sync with this remote prefilled as the source.
   - **Edit** opens `EditRemoteSheet`.
2. **Gauge.** 14 pt bar, used segment in accent, free in `surfaceSubtle`, legend below
   with "Used 1.28 TB" and "Free 720 GB". Hidden entirely when quota is unknown; the
   header subtitle then shows just the provider.
3. **Tabs** (`Picker`, `.segmented` is wrong here; use a custom underline tab bar built
   from tokens, matching the mockup): **Files · Transfers · Finder · Settings**.
   - **Files**: the existing `BrowserView` body (breadcrumb, table/grid, toolbar actions).
     The toolbar items it contributes (back/forward, new folder, refresh, view mode, sort)
     appear only while Files is selected.
   - **Transfers**: the existing `TransfersView` list filtered to transfers whose source
     or destination is this remote, with the same filter menu and Clear Completed.
   - **Finder**: this remote's mount configurations, reusing `MountRow`, `MountInspector`,
     and `AddMountSheet` from the old Finder pane, scoped to `config.remoteNameOnly ==
     name`. Empty state offers "Show in Finder" (File Provider) and "Mount as Network
     Volume…" (NFS).
   - **Settings**: read-only summary of the rclone config (type, non-secret keys), with
     **Edit Configuration…** and a destructive **Remove Volume…** that uses the existing
     delete confirmation.
   - Selected tab persists per remote for the session only.
4. **Transfer drawer.** Shown at the bottom of the pane whenever any transfer is active,
   regardless of remote. Header row: "Transfers · N active · speed", chevron to collapse.
   Body: active `TransferRow`s, max four, then "+N more" which switches to the Transfers
   tab. Collapsed state persists for the session.

### Inspector (from Direction 1)

- Toolbar toggle (`sidebar.right`) shows a 240 pt trailing inspector in the Files tab.
- Content for a single selection: large `FileIcon`, name, cloud status pill
  (`StatusBadge` pill style, this is where the labelled pill now lives), key/value list
  (Kind from UTType, Size, Modified, Location as remote › path), and actions **Quick Look**
  and **Copy to…** (opens `ConfirmCopySheet` flow via a target picker; v1 can reuse
  `FolderBrowserSheet`).
- Multiple selection: count and total size. No selection: the current folder's name and
  item count.
- Inspector visibility persists in `AppSettings` (`inspectorVisible`).

### Toolbar

- Title is the volume name (already via `.navigationTitle`).
- **Add Volume** replaces the sidebar `+` as the primary way to add a remote (the sidebar
  menu stays for Import).
- **Transfer pill**: when transfers are active, a capsule showing "N items to <dest>" with
  a mini progress bar. Clicking selects the Transfers tab of the current volume.
- Inspector toggle at the trailing edge.

### Quota data

- `RemoteStatusService` gains `quotas: [String: AboutResponse]` and `refreshQuota(_:)`,
  called after a successful probe and every 5 minutes while the remote is selected. A
  failed `about` leaves the quota absent (never an error state; many backends don't
  support it).

### Onboarding

- Unchanged in flow. The second card's secondary action text becomes "Show it in Finder".

### Settings window

- Unchanged.

## Removed

- `MountsView` as a top-level pane (its pieces move into the Finder tab).
- `TransfersView` as a top-level pane (its list becomes the Transfers tab; its empty state
  copy becomes "No transfers for this volume yet.").
- `SidebarSelection.mounts` and `.transfers`. Keyboard shortcuts that targeted them are
  remapped: ⌘2 selects the Transfers tab of the current volume.

## Constraints

- `.system(size:)` lint and no remote SPM packages still apply.
- The Finder tab must keep the File Provider toggle semantics documented in `MountsView`
  (intent flips first, domain registration reconciles in the background).
- Tests: `SidebarSelectionTests`, `MountRowTests`, `TransferRowTests` keep passing;
  add tests for the quota formatting and the per-remote transfer filter.

## Left to the builder

- Exact gauge height and legend typography (match the mockup's weight, use tokens).
- Whether the drawer animates with `DesignSystem.Motion.smooth` (yes, unless it fights
  the table's resize).
- How "Copy to…" picks a destination in v1; reuse over new UI.
