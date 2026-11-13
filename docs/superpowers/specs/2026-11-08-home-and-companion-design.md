# Home and Companion — Design

**Date:** 2026-11-08
**Status:** Direction approved ("Home + Companion" from the mockup review page). Phase 1 implemented 2026-11-08 on `feat/home-phase1`; see "Phase 1 as built" at the end.
**Mockups:** `docs/mockups/interface-directions.html`, sections Home and Companion
**Builds on:** `2026-11-08-volumes-redesign-design.md` (the Volumes pane stays as each cloud's detail page)

## Why

Nimbus should be easy for anyone, not only for people who know rclone. Today the window opens
on the first remote's file browser, and the words on screen come from rclone: remote, volume,
mount, "rclone connected", "Alias for an existing remote". The question a non-technical person
asks most often is "is everything working?", and nothing answers it in one glance.

This design adds two things that answer that question, plus a vocabulary pass:

1. **Home**, the window's landing screen. It shows every cloud's capacity and health in plain
   sentences, and gives any problem the button that fixes it.
2. **Companion**, a menu bar window. It shows the same status while the main window is closed,
   because Finder (through File Provider) is where most people browse.

Power users lose nothing. Every cloud row opens the existing Volumes pane, and its Files tab is
unchanged.

## Goals

1. The window opens on Home. One storage bar covers all clouds, there is one row per cloud with
   a plain-language status, and at most one attention banner at a time.
2. The menu bar shows aggregate state through its glyph. Clicking it opens a window with live
   transfers, the clouds, recent activity, and quick actions.
3. Home and the menu bar compute status from one shared, unit-tested model, so the two
   surfaces never disagree.
4. No rclone vocabulary appears on any screen outside Settings › Advanced and the Volumes pane's
   Settings tab.
5. Add Cloud leads with recognizable services as tiles, each with a one-line hint about how
   sign-in works.

## Non-goals

- **Scheduled backups.** The mockup's "Backups" sidebar item, "Back up your Desktop" suggestion,
  and "Backups to this cloud" section all need a scheduler, which Nimbus doesn't have yet. They
  are cut from v1.
- **Local-cache cleanup.** The "Free up 38 GB of downloads" suggestion and the "Free up space
  automatically" toggle need per-domain File Provider eviction accounting. They are cut from v1.
- **Settings-style per-cloud pages** (the Companion mockup's second screen). The Volumes pane
  stays the detail page. Its Settings tab gets the vocabulary pass, not a rebuild.
- **Pausing transfers.** rclone has no per-job pause over RC, and a bandwidth-limit hack would
  pause every job at once. v1 shows progress and a "Show Transfers" button only.
- Changes to the File Provider extension, RcloneKit's API surface, or design-token files.

## Corrections to the mockups

The mockups ran ahead of what Nimbus can truthfully say. The build follows this spec, not the
mockups, wherever the two differ:

| Mockup | Spec | Reason |
|---|---|---|
| "Up to date" | "Ready" | Nimbus does not track per-file sync state, so "up to date" would be a claim it can't verify. |
| "Your sign-in stays in your Mac's keychain" | "You sign in on Google's own page. Nimbus never sees your password." | rclone stores OAuth tokens in `rclone.conf`, not the keychain. |
| Pause button on the transfer header | "Show Transfers" button | There is no pause over RC (see non-goals). |
| "Recently changed" files in the menu bar | "Recent activity" from transfer history | Nimbus does not observe File Provider changes. Transfer history is real data. |
| Activity and Backups sidebar items | Cut | Activity lives on Home and in each cloud's Transfers tab. Backups needs a scheduler. |
| Step order Choose › Sign in › Name it | Choose › Name it › Sign in (or Set up) | `RemoteSetupFlow` asks for the name before the rclone state machine starts. |

## Shared model: `CloudSummary`

Home and the menu bar render the same values. A pure builder produces them:

```swift
struct CloudSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String              // remote name
        let providerType: String    // for ProviderIcon / ProviderBadge
        let providerName: String    // "Google Drive"
        let health: Health          // drives dot color and banner eligibility
        let sentence: String        // "Ready", "Needs sign-in", "Uploading 3 files, 2 min left"
        let quota: StorageQuota?
        let isInFinder: Bool
        let tint: TintSlot          // stable color for the aggregate bar
        let lastConnected: Date?
    }
    enum Health { case ready, busy, checking, needsSignIn, unreachable, failing }
    enum Overall { case allReady, busy(progress: Double, sentence: String), needsAttention(Row), noClouds, engineDown }

    let rows: [Row]
    let overall: Overall
    let usedBytes: Int64            // sum of known `used`
    let freeBytes: Int64?           // sum of `free` over clouds that report a total; nil if none do
    let attention: Row?             // highest-priority problem, or nil
}

enum CloudSummaryBuilder {
    static func build(remotes: [Remote], statuses: [String: RemoteStatus],
                      quotas: [String: StorageQuota], transfers: [Transfer],
                      finderShown: (String) -> Bool, providerName: (String) -> String,
                      lastConnected: [String: Date], daemon: RcloneDaemon.Status,
                      now: Date) -> CloudSummary
}
```

The builder lives in `State/CloudSummary.swift`. It owns no state and is covered by unit tests.

### Status sentences

These are evaluated in order, and the first match wins:

| Condition | Health | Sentence |
|---|---|---|
| Daemon not connected | — | Overall `engineDown`: "Nimbus's connection engine stopped." Button: **Restart** |
| Active transfer whose `dstFs` is this cloud | busy | "Uploading N files, <eta> left" (no eta: "Uploading N files") |
| Active transfer whose `srcFs` is this cloud | busy | "Downloading N files, <eta> left" |
| `.authNeeded` | needsSignIn | "Needs sign-in" |
| `.error` classified as network unreachable (`URLError` cannot connect / host not found, rclone "connection refused", "no route to host") | unreachable | "Can't reach this server right now" |
| `.error` other | failing | "Can't connect" (the detail is shown in the Volumes pane) |
| `.unknown` | checking | "Checking…" |
| `.connected` | ready | "Ready" |

`RemoteStatusService.classify` gains the `unreachable` split as a new `RemoteStatus` case,
`.unreachable(reason:)`, so the Volumes header can use it too.

Under "Can't reach this server right now", the row shows "Last connected <relative date>" when
`lastConnected` is known.

### Attention priority

Only one banner shows at a time: `needsSignIn` first, then `failing`, then `unreachable` for
clouds that have been unreachable for over 24 hours. Ties go to sidebar order. Busy and
checking clouds never get a banner.

| Health | Banner title | Body | Button |
|---|---|---|---|
| needsSignIn | "<Cloud> needs you to sign in again" | "<Provider> ended the session. Files already on this Mac are safe; new changes wait until you sign in." | **Sign In to <Provider>** |
| failing | "Nimbus can't connect to <Cloud>" | first line of the rclone error, rewritten by `NimbusError` when known | **Show Details** (opens the Volumes pane) |
| unreachable | "<Cloud> has been unreachable since <date>" | "If it's on your home network, it will reconnect when you're back." | **Try Again** (re-probe) |

### Aggregate bar math

- Each cloud contributes its `used` value as one segment. Clouds without a `used` value
  contribute nothing.
- Denominator = the sum of `total` over clouds that report a total, plus `used` for clouds that
  report usage without a total (B2, S3). This way the bar never overflows, and pay-as-you-go
  storage still takes up room.
- Header text is "<used> used" plus ", <free> free" when `freeBytes` is non-nil. Free space is
  never invented for clouds without a limit.
- Legend lines: "<Cloud> 1.28 TB", "<Cloud> 720 GB, billed by what you store" (usage without a
  total), "<Cloud> not reachable" (no quota and not ready).
- **Tints** come from a fixed slot list of system colors, assigned in sidebar order: blue, teal,
  indigo, orange, pink, green, yellow, then gray. Brand colors are not used, because two Google
  Drive accounts would share one. A slot follows its cloud until the cloud is removed.

### Last connected

`AppSettings.lastConnected: [String: Date]`, persisted. `RemoteStatusService.probe` writes it
whenever a probe returns `.connected`, and `clear(_:)` removes the entry.

## Home

### Navigation

- `SidebarSelection` gains `.home` as its first case. `nextSelection` returns `.home` when the
  current selection is nil or a deleted remote (today it returns the first remote). Tests are
  updated to match.
- The sidebar gets a **Home** row (`house`) above the Clouds section. The Clouds section header
  is renamed from Volumes, and its rows and capacity bars are unchanged.
- The Tools section's "Copy & Sync" row is renamed **Copy Between Clouds**. The view itself is
  unchanged.
- The status bar at the bottom of the sidebar is removed. Daemon health moves into Home's
  `engineDown` state and the menu bar glyph.

### Layout (`Views/Home/HomeView.swift`)

The layout follows the Home mockup. From top to bottom:

1. **Toolbar:** the title "Home", then **Copy Between Clouds…** (secondary) and **Add Cloud**
   (prominent), which replace the sidebar "+" as the main entry point. Import from rclone.conf
   stays in the sidebar "+" menu and in Add Cloud.
2. **Storage overview:** a grouped box containing the header line, a segmented 22 pt bar
   (`HomeStorageBar`), and the legend. Segment widths animate with `DesignSystem.Motion` when
   quotas arrive. For accessibility it is one element whose label reads like "Personal 1.28 TB,
   Work 412 GB…".
3. **Attention banner** (when present): it uses `statusWarning` for needsSignIn and unreachable,
   and `statusError` for failing.
4. **Two columns** below the banner: the main column holds the list, and a 270 pt side column
   holds the other two sections. Below 900 pt of width they stack into one column.
   - **Your clouds:** a grouped list. Each row shows a `ProviderBadge` (40 pt), the name, the
     dot plus status sentence, an "In Finder" tag, usage text with a 150 pt bar, and a chevron.
     Clicking a row selects `.remote(name)`. The context menu offers Open in Finder / Show in
     Finder, Copy Between Clouds…, and Edit.
   - **Worth a look:** shown only when there is something to show. v1 has just two
     suggestions, both computable today:
     - The cloud is ≥ 90% full: "<Cloud> is almost full", with "<free> left of <total>." and the
       button **Open <Cloud>**.
     - The cloud is not in Finder and has been ready for over 24 hours: "<Cloud> isn't in
       Finder yet", with "Show it under Locations so you can open files from any app." and the
       button **Show in Finder**. Dismissing it (×) records the cloud in
       `AppSettings.dismissedSuggestions`.
   - **Recent activity:** the last 5 finished transfers from `TransferStore` history. Each line
     reads "Copied <last path component of src> to <dst cloud>" (or Moved or Synced), with a
     relative time underneath. A failed transfer reads "Couldn't copy …" and its row opens that
     cloud's Transfers tab.
5. **Empty and engine-down states** replace the body:
   - No clouds: the app icon, "Add your first cloud", "Google Drive, Dropbox, OneDrive, your NAS,
     and <N> more.", where N comes from `ProviderDirectory`, never a hard-coded number, and **Add Cloud**.
   - Engine down: "Nimbus's connection engine stopped", with the daemon message in secondary
     text and the button **Restart**, which calls `daemon.retry`.

## Companion (menu bar)

### Glyph

`MenuBarExtra` switches to `.menuBarExtraStyle(.window)`. Its label is a template SF Symbol
driven by `CloudSummary.overall`:

| Overall | Symbol |
|---|---|
| allReady, noClouds | `icloud` |
| busy | `icloud.and.arrow.up` (any upload) or `icloud.and.arrow.down` |
| needsAttention, engineDown | `exclamationmark.icloud` |

The label also gets an accessibility description, such as "Nimbus: uploading 3 files".

### Window (`Views/Companion/CompanionView.swift`, 340 pt wide)

1. **Header:** the overall sentence ("Everything is ready", "Uploading 3 files to Dropbox",
   "Work needs you to sign in"). While busy, it also shows a linear progress bar and
   "<done> of <total>, about <eta> left", plus **Show Transfers**, which opens the main window
   on that cloud's Transfers tab.
2. **Clouds:** one row per cloud with a 28 pt badge, the name, and the status sentence (with
   capacity when ready: "1.28 TB of 2 TB"). A needsSignIn row has an inline **Sign In** button.
   Clicking a row opens the main window on that cloud. Unreachable rows are dimmed.
3. **Recent activity:** the last 3 lines of the Home feed.
4. **Footer:** **Add Cloud…** (opens the main window, then the sheet), **Open Nimbus**, and a
   gear menu with Settings…, an **Open at Login** checkmark item (bound to the existing
   launch-at-login setting), and Quit Nimbus.

### State outside the window

The menu bar must be right while the main window is closed, which requires two changes:

- **Lift the remote list to app scope.** Today `RemotesSidebarSection` creates its own
  `RemotesViewModel`, and `ContentView` receives the list through a callback. A single
  `RemotesViewModel` is created in `NimbusApp`, loaded in `onDaemonConnected`, and injected into
  the window scene and the `MenuBarExtra`. The sidebar and `VolumeSettingsTab` read it from the
  environment instead of building their own.
- **Periodic probes.** `RemoteStatusService` stops being fire-once. It probes all clouds on
  daemon connect, every 10 minutes after that, and when the companion window opens if the last
  probe is older than 2 minutes. The class comment changes to match. A probe that is already
  in flight for a cloud is not started twice.

## Vocabulary pass

These are UI strings only. Type and file names (`Remote`, `VolumeView`, `MountManager`) stay as
they are.

| Today | New |
|---|---|
| Volumes (sidebar header), Volume | Clouds, cloud |
| Add Volume / Add Remote | Add Cloud |
| No Volumes Yet | Add your first cloud |
| Remote (in user-facing copy) | Cloud |
| Mount, File Provider domain | Show in Finder / In Finder |
| Mount as Network Volume… | Connect as Network Drive… (advanced; Finder tab only) |
| Alias for an existing remote | the target's provider name, resolved through the alias |
| rclone connected / rclone Isn't Running / Connecting to rclone… | (hidden) / Nimbus's connection engine stopped / Starting… |
| Copy & Sync | Copy Between Clouds |
| ● Connected / ⚠ Sign In / ! Error (status pills) | Ready / Needs sign-in / Can't connect |
| Token expired, 401, 403 | "<Provider> signed you out." |

Settings › Advanced and the Volumes pane's Settings tab keep rclone terms. They are labelled
"rclone settings" so power users still know where to look.

## Add Cloud picker

`ProviderPicker` keeps its rows for the long tail but changes how it opens:

1. **Popular** becomes a 4 × 2 grid of tiles: `ProviderBadge` at 40 pt, the name, and a hint.
   The hint is "Sign in with <Brand>" for OAuth backends. For others it comes from a small
   table: iCloud Drive "Uses your Apple Account", pCloud and MEGA "Email and password", Proton
   Drive "End-to-end encrypted".
2. **Storage you run or rent:** chips for S3 and compatible, Backblaze B2, NAS or server
   (SFTP), WebDAV, and **Import from rclone.conf…**.
3. **All services:** the existing alphabetical rows.
4. When the search box has text, the tiles are replaced by the filtered rows, as they are today.
5. A step indicator across the sheet shows Choose a service › Name it › Sign in, where step 3 is
   labelled "Set up" for non-OAuth backends. It reflects the `RemoteSetupFlow` phase.
6. The footer note for OAuth providers reads "You sign in on <Brand>'s own page. Nimbus never
   sees your password." Other providers get no note. The primary button reads **Continue with
   <Provider>**, or **Continue** when nothing is selected (disabled).

This overrides the "Changing `ProviderPicker`" non-goal in `2026-08-30-guided-add-remote-design.md`.
The `RemoteSetupFlow` state machine is untouched.

## Re-sign-in

**Sign In to <Provider>** has to re-run OAuth for an existing remote. Before Phase 1 builds
this button, someone must check against rclone 1.74 whether `config/update` with
`opt: {continue:…, state:…}` walks the same `*oauth-islocal` states as `config/create` does
for an existing remote. The CLI equivalent is `rclone config reconnect`.

- If it does, add `RemoteSetupFlow.reconnect(remote:)`, which reuses `OAuthStep`.
- If it doesn't, the button opens `EditRemoteSheet` scrolled to the token field, and the
  banner copy changes to "Open settings to sign in again". Record the finding in the maintainer's notes.

## Phasing

Each phase is its own PR and must work on its own.

1. **Home and vocabulary:** `CloudSummary` with tests, the `.unreachable` status,
   `lastConnected`, `.home` selection, `HomeView`, the sidebar changes, the string pass, and the
   re-sign-in investigation.
2. **Companion:** the remote list lifted to app scope, periodic probes, `.window`-style
   `MenuBarExtra`, the glyph mapping, and `CompanionView`.
3. **Add Cloud picker:** tiles, chips, step indicator, and footer copy.

## Exit gates

- `CloudSummaryBuilder` unit tests cover every row of the status-sentence table, the attention
  priority order, bar math with mixed quota shapes (total plus used, used only, neither),
  stable tint slots across reorder and delete, and engine down.
- `nextSelection` tests cover `.home` as the default and the fallback after a remote is
  deleted.
- RenderPreview of `HomeView` in light and dark with these fixtures: all ready, one needs
  sign-in, busy, no clouds, engine down. RenderPreview of `CompanionView` with the same five.
- Manual check: revoke a Google Drive token, confirm the banner, the menu bar glyph, and the
  companion row all change within one probe cycle, and confirm **Sign In** fixes it.
- Manual check: close the main window, start a cross-cloud copy from Finder drag, and watch the
  glyph and header progress.
- Zero new compiler warnings. VoiceOver reads the storage bar and each cloud row as one
  sentence each.
- Grep check: no "remote", "volume", "mount", or "rclone" in user-facing strings outside the
  allowed screens.

## Phase 1 as built (2026-11-08)

Where the build differs from the sections above, the build wins:

- **Re-sign-in is verified and shipped.** On rclone 1.76, `config/update` on an existing drive
  remote walks `client_id_warning` (`config_shared_client_id`), then `*oauth-confirm`
  (`config_refresh_token`, "Token already configured - replace it?"), then `*oauth-islocal`.
  RcloneKit gained `startUpdate`/`continueUpdate`. `ReconnectFlow` auto-answers only those three
  questions and stops as soon as the browser step returns, so later questions (for example
  OneDrive's drive picker) never change the config. Any other question before sign-in ends
  in "needs more than a sign-in" instead of a guess.
- **Busy sentences say "items", not "files".** A `Transfer` is an rclone job, and Nimbus doesn't
  know how many files it holds.
- **`lastConnected` lives in `RemoteStatusService`**, persisted under `remoteLastConnected`,
  not in `AppSettings`. The service is the place that knows when a probe succeeds.
- **The "not in Finder" suggestion has no 24-hour wait.** Nimbus records no "ready since" time.
  The suggestion is dismissible instead.
- **Clicking an activity line opens that cloud**, not its Transfers tab, because the tab is
  private state of the Volumes pane.
- **Aliases resolve to the service they point at** (`CloudNaming`): the badge and provider name
  come from the target, and an alias of a local folder reads "Shortcut to a folder".
- **Home is split into `HomeView`** (reads services) **and `HomeContent`** (pure, with five
  fixture previews), which gives the RenderPreview exit gate something to render without a
  daemon.
- **The sidebar's rclone status bar is gone.** Daemon state shows only on Home.
- **Not verified in the running app.** On daemon connect, Nimbus removes any File Provider domain
  whose remote isn't in the active config (`cleanupStaleDomains`), so launching with a demo
  `RCLONE_CONFIG` on a Mac that has real domains would remove them. Verification used
  RenderPreview and unit tests. A real-app check needs a Mac or user account with no real
  Nimbus domains.

## Phase 2 as built (2026-11-08)

- **`CloudMonitor`** (`Services/CloudMonitor.swift`) owns the app-wide cloud list and refresh
  cadence. It refreshes on every daemon connect, every 10 minutes, on `.nimbusRemotesChanged`,
  and when the companion opens with data older than 2 minutes. Concurrent refreshes share one
  run, and a failed list load keeps the previous list. This replaces the per-sidebar
  `RemotesViewModel`. Selection reconciliation waits for `hasLoaded`.
- **`AppRouter`** (`State/AppRouter.swift`) carries one-shot requests into the main window:
  `.home`, `.cloud`, `.transfers`, `.signIn`, `.addCloud`. Because it's state rather than a
  notification, a request survives the window being re-created to handle it. It replaces the
  Phase 1 `.nimbusAddCloudRequested` notification. The main `WindowGroup` now has the id `main`.
  The companion brings an open window forward, or calls `openWindow(id:)` when the window was
  closed.
- **`Busy` gained `direction`, `focusCloud`, and `eta`.** A batch whose destinations are all
  local paths reads "Downloading N items to this Mac" and shows the down-arrow glyph.
- **The companion header asks for attention before showing progress**, the same priority Home
  uses. "Copying" is shown even for uploads, because one batch can mix uploads and cloud-to-cloud
  copies.
- **The gear menu has Settings…, an Open at Login toggle** (bound to `LaunchAtLoginService`),
  and Quit Nimbus.
- **Verified with RenderPreview of `CompanionContent`** (busy in light, needs sign-in in dark,
  plus all-ready, no-clouds, and engine-down fixtures) and unit tests. Not run in the live app,
  for the same File Provider domain-cleanup reason as Phase 1.

## Phase 3 as built (2026-11-08)

- **`PickerCatalog`** in `ProviderPicker.swift` holds the plain titles and sign-in hints for the
  8 popular services and the 4 server chips, plus the OAuth set (drive, dropbox, onedrive,
  box, pcloud). **Correction to the table above:** pCloud signs in through the browser, so
  its hint is "Sign in with pCloud", not "Email and password". OneDrive reads "Personal or
  work account".
- **One click picks a service; there's no separate "Continue with <Provider>" button.** The
  tiles and chips are buttons, as the rows were before, which saves a step. The "Nimbus never
  sees your password" line stays where sign-in happens (`OAuthStep`), not on the picker.
- **"Import from rclone.conf…" is the last chip.** It opens `ImportConfigSheet` on top of Add
  Cloud. Import can't report cancel vs. success, so Add Cloud stays open afterwards. Its
  `onDismiss` refreshes the cloud list.
- **`SetupSteps`** (`Components/SetupSteps.swift`) is the labelled three-step strip. Step 3
  says "Sign in" or "Set up" based on `RemoteSetupFlow.isOAuthBackend`, falling back to
  `PickerCatalog.isOAuth` before rclone has answered. The sheet grew to 600 × 600.
- **The search prompt counts the services rclone actually reports** ("Search 72 services"), and
  search also matches the plain titles ("OneDrive", "NAS").
- **The `ProviderPicker-sections` fixture was re-recorded.** It renders through `ImageRenderer`
  at a forced 2x scale, so recording on a non-Retina display is safe. That is not true of the
  window-based Settings fixtures.
