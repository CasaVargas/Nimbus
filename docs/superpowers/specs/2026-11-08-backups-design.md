# Backups — Design

**Date:** 2026-11-08
**Status:** Approved 2026-11-08 with the defaults below (open questions resolved to the spec's proposals). Phase 1 shipped in #25 (2026-11-08); phases 2 and 3 not started.
**Roadmap:** item 2 of the competitive research's recommended order (Tolaria
`nimbus/nimbus-competitive-feature-gaps-research.md`), and the north star's phase 4 "scheduled syncs".
**Builds on:** `Views/CopySync/` (the one-off copy/sync screen), `State/TransferStore.swift`,
`2026-11-08-home-and-companion-design.md` (which cut Backups from v1 because there was no scheduler).
**Plan:** `docs/superpowers/plans/2026-11-08-backups.md`

## Why

Nimbus can copy one folder to another once, by hand. Every competitor that matters for this
audience (RcloneView, Transmit 6, CloudMounter's paid tier) also lets you save that copy, run it on
a schedule, see what it will do before it does it, and get back the files it replaced. Without that,
"back up my Documents to B2 every night" means a cron job and the rclone CLI, which the north star
says Nimbus must never require.

A backup feature is also where a cloud app can do the most damage. A mirror (sync) to the wrong
folder, or from a source that is suddenly empty, deletes real data on a timer while nobody watches.
The design leans on three guards: a preview before anything runs, versions that keep replaced and
deleted files, and a removal limit that stops a run that is about to remove too much.

## Goals

1. **Saved backups.** Each one has a name, a source, a destination, a mode (mirror or add-only),
   excludes, versions on or off, and a schedule. Either side can be a cloud folder or a folder on
   this Mac.
2. **A schedule that runs on its own** while Nimbus is running (menu bar included), and catches up
   once on a run it missed while the Mac was asleep or Nimbus was closed.
3. **A preview** (rclone dry run) that lists what would be copied, replaced, and removed. It is
   required before the first run and again after any change that alters what a run does, and
   available on demand.
4. **Versions.** Replaced and removed files are moved into a dated folder on the destination
   instead of being lost (`--backup-dir`).
5. **History and notifications through the existing Transfers machinery.** A backup run is a
   `Transfer` with `origin: .backup`. It shows in the involved clouds' Transfers tabs, in Home's
   recent activity and in the menu bar, and it notifies through `TransferNotificationService` under
   the existing notification setting.
6. **No lock-in.** Jobs live in one plain JSON file. Every job can be copied as the equivalent
   `rclone` command.

## Non-goals

- **Running while Nimbus is quit.** See decision 1. Nimbus runs as a menu bar app and already has
  Open at Login; that is the contract for v1.
- **Two-way sync (bisync).** The research put it on hold. A backup goes one way.
- **Restoring from inside Nimbus.** v1 shows where the versions are (**Show Versions** opens the
  folder in the browser or Finder); you restore by dragging files back. A restore wizard is later
  work.
- **Per-job bandwidth or transfer limits.** Runs use the app-wide settings the daemon was started
  with.
- **"Only on power adapter" and "only on Wi-Fi X" conditions.**
- **Encrypting backups.** That is roadmap item 4 (crypt "encrypted folder"). A backup whose
  destination is a crypt remote already works, because a crypt remote is just a remote.
- **Changes to the File Provider extension.**

## Anti-goals

- A scheduled run must never remove destination files that the user did not see in a preview.
  The preview gate (below) is the mechanism; nothing bypasses it, including **Back Up Now**.
- No second rclone process that writes `rclone.conf` behind the daemon's back (see decision 1).
- No proprietary job format, and no state that exists only in `UserDefaults`.
- No subscription, account, or Nimbus-run server, now or later.

---

## Decision 1: where the schedule runs

### Options considered

| Option | How it works | For | Against |
|---|---|---|---|
| **A. In the app (chosen)** | A `BackupScheduler` inside Nimbus starts runs on the daemon Nimbus already owns. Nimbus keeps running after its window closes (`applicationShouldTerminateAfterLastWindowClosed` returns `false`) and can open at login (`LaunchAtLoginService`). | One rclone process, one `rclone.conf` writer, live progress in Transfers and the menu bar, no new target to sign and notarize. Small. | Nothing runs while Nimbus is quit. |
| B. LaunchAgent runs rclone | A bundled agent (`SMAppService.agent(plistName:)`) wakes at the scheduled times and runs `rclone sync` itself. | Runs with Nimbus quit. | A second rclone process refreshes OAuth tokens and rewrites `rclone.conf` while the daemon may be doing the same. Nimbus already has a gotcha where one partial `rclone.conf` read destroyed a File Provider domain (Tolaria `nimbus-fileprovider-rclone-contract-gotchas`, item 4). No live progress; history would arrive by file. `SMAppService` agents need a static plist in the bundle, so per-job times require a fixed polling interval or rewriting `~/Library/LaunchAgents` by hand. macOS shows a "background item added" notice. A config password (roadmap item 4) would need a second unlock path. |
| C. LaunchAgent that only launches Nimbus | The agent runs `open -g -b app.casavargas.nimbus` near the scheduled time. | One rclone process. | Relaunches an app the user chose to quit, which surprises people. Same static-plist problem as B. Adds little over A plus Open at Login. |
| D. Login-item helper owns the daemon | An always-running helper (`SMAppService.loginItem`) owns rclone; the app and the extension become its clients. | The "right" long-term shape (Dropbox-like). | It re-architects daemon ownership, the port hand-off to the File Provider extension, NFS mounts, and quit handling. It's a project of its own, not part of Backups. |

### Choice

**A.** Backups run while Nimbus is running, in the window or only in the menu bar. The app is not
sandboxed (`com.apple.security.app-sandbox` is `false`), so sandboxing doesn't push us towards a
helper. The rclone daemon's lifecycle does: there should be exactly one rclone process that
touches `rclone.conf`.

What the user sees:

- When a backup with a schedule is saved and Open at Login is off, the editor shows: "Scheduled
  backups run while Nimbus is open, including from the menu bar." with an **Open at Login** toggle
  bound to `LaunchAtLoginService`. The Backups screen footer repeats it while any job has a
  schedule and Open at Login is off.
- **Quit Nimbus** while a backup is running asks first: "A backup is running. If you quit, it
  stops and runs again the next time Nimbus opens." with **Quit** and **Cancel**. No prompt when
  nothing is running.

Revisit D if people ask for backups with Nimbus quit. The scheduler is written against a small
protocol (`BackupLaunching`) so a future helper can own it.

### Schedule semantics

- **Kinds:** Manual only, Every hour, Every day at a time, Every week on a weekday at a time. Times
  are wall-clock in the Mac's current time zone. `Calendar.nextDate(after:matching:)` does the math,
  so DST gaps and repeats follow Foundation's rules (a 2:30 AM run on a spring-forward day runs at
  3:00 AM).
- **Next run** = the first slot after the start of the last attempt (or after the job was
  approved, if it has never run). A failed run is not retried early; it notifies and runs again
  at its next slot. **Back Up Now** doesn't move the schedule.
- **Missed runs.** When Nimbus starts, wakes from sleep, or the daemon reconnects, any job whose
  next run is in the past runs **once**, not once per missed slot, after a 60-second settle delay so
  the network and login-item retries finish first. A run cut off by quit or a crash has no
  finished record, so it counts as missed and runs on the next launch.
- **One run at a time.** Backup runs go through a FIFO queue. A job that is already queued or
  running isn't queued again. Ordinary copies and drags don't wait for the queue.
- **Sleep.** While a backup runs, Nimbus holds
  `ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled], reason:)`, so the Mac doesn't idle-sleep in
  the middle. Nimbus cannot wake a sleeping Mac (that needs root `pmset`); a 2 AM run on a sleeping
  laptop runs on wake, the way Time Machine catches up.
- **Paused** jobs keep their schedule but don't run; the row says "Paused".
- **Timer.** One `Task` sleeps until the earliest next run, and re-plans on job edits,
  `NSWorkspace.didWakeNotification`, `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange`, and
  daemon reconnect. Clock and calendar are injected so the planner is unit-tested without waiting.

## Decision 2: how the dry run maps onto rclone

### Verified against rclone 1.76 (`rclone rcd` on a scratch folder, 2026-11-08)

- `sync/sync` and `sync/copy` accept `_config: {"DryRun": true}`. Nothing on disk changes. The
  setting applies to that call only; `options/get` afterwards still shows `DryRun: false`.
- Both accept report flags. With `_async: true` the reports arrive in `job/status`'s `output`:

  ```json
  "output": {
    "missingOnDst": ["new.txt"],
    "differ": ["sub/changed.txt"],
    "missingOnSrc": ["onlydst.txt"],
    "error": []
  }
  ```

  `combined: true` gives the same information as `"+ new.txt"`, `"* sub/changed.txt"`,
  `"- onlydst.txt"`, plus `"= same.txt"` for **every** unchanged file. Nimbus asks for the
  separate lists and never for `match`/`combined`, so a 200,000-file backup with 12 changes returns
  12 strings, not 200,012.
- **`sync/copy` reports destination-only files in `missingOnSrc` too, although copy never removes
  them.** For add-only jobs Nimbus doesn't request `missingOnSrc`.
- `_filter: {"ExcludeRule": [...]}` applies to the dry run exactly as to the real run.
- `_config: {"BackupDir": ...}` in a real run moved both the overwritten file and the removed
  file into the backup folder, keeping their relative paths.
- A backup folder **inside** the destination fails ("destination and parameter to --backup-dir
  mustn't overlap") **unless** a filter excludes it. `ExcludeRule: ["/.nimbus-versions/**"]` made
  it pass.
- `_config: {"MaxDelete": N}` counts moves into the backup folder as removals. When the limit is
  hit, rclone removes N files and then fails the job with "failed to delete K files". With
  `DryRun` it reports the same failure without removing anything, so a preview can warn about it.
- A missing source folder fails with "directory not found" and removes nothing. An **empty**
  source folder mirrors to an empty destination, which is the disaster the removal limit exists
  for.
- `core/stats` for the job's group (`job/<id>`) gives `transfers`, `deletes`, `renames` (moves
  into versions), `errors`, `listed`, and `totalBytes`. `core/transferred` returns only the last
  100 items, so it's not used for previews.

### Mapping

| Job setting | RC parameter |
|---|---|
| Mode mirror / add-only | `sync/sync` / `sync/copy` |
| Excludes | `_filter.ExcludeRule` (user patterns, plus the versions folder when it's inside the destination) |
| Versions on | `_config.BackupDir = <versions fs>/<run stamp>` (stamp `yyyy-MM-dd HHmmss`, local time) |
| Removal limit (mirror only) | `_config.MaxDelete` |
| Preview | the same call plus `_config.DryRun = true` and the report flags |
| Run | the same call without `DryRun`; no report flags (counts come from `core/stats`) |

Preview and run build their parameters from **one** function, `BackupRequest.make(job:dryRun:
stamp:)`, so a preview can't drift from what the run does. The CLI equivalent for **Copy rclone
Command** comes from the same struct.

### Capturing results for display

1. `BackupPreviewer` starts the dry run (`_async: true`) and polls `job/status` every 250 ms. It
   shows `listed` from `core/stats` as "Checking… 12,400 items". rclone forgets finished jobs after
   `--rc-job-expire-duration` (60 s by default), and polling at 250 ms reads the output long before
   that.
2. On finish it decodes `output` into `SyncReport { missingOnDst, differ, missingOnSrc, error }`
   and reads `core/stats` once for `totalBytes`.
3. The result is a value, `BackupPreview { willCopy, willReplace, willRemove, errors, approxBytes,
   limitHit, finishedAt, fingerprint }`. It lives only in memory; the sheet shows it, and approving
   it stores the fingerprint (below) on the job.
4. Closing the sheet while the dry run is still going calls `job/stop`.
5. Previews are not `Transfer`s and don't appear in Transfers or history. They don't transfer
   anything.

### The preview gate

A job's **fingerprint** is a SHA-256 over the canonical JSON of what decides a run's effect:
source, destination, mode, excludes, versions on/off and location, removal limit. Name and
schedule are not part of it.

- `job.approvedFingerprint` is set when the user presses **Approve** (or **Approve and Back Up
  Now**) on a preview that finished without errors.
- A job runs, by schedule or by **Back Up Now**, only when `approvedFingerprint ==
  fingerprint(job)`. Otherwise its row says "Preview needed" and **Back Up Now** opens the
  preview instead.
- Editing any fingerprinted field clears the approval. Renaming or rescheduling does not.
- A preview with errors can't be approved; it shows the errors and offers **Edit**.
- A preview whose `willRemove` count exceeds the removal limit (or reports `limitHit`) can be
  approved only after a second confirmation that names the count: "This backup will move 4,812
  files out of B2/Mac into versions."

This gate stops "wrong destination" and "wrong mode" on the first run. Later runs are covered by
versions and the removal limit, not by a fresh preview each time: a dry run before every
scheduled run would list both sides twice, which costs real time and API calls on large clouds.

## Decision 3: where jobs are stored

### Options considered

| Option | For | Against |
|---|---|---|
| `UserDefaults` | No code to write. | Not a file you can read, copy, or back up by name; opaque plist domain. Fails "files-first". |
| One file per job (`Backups/<uuid>.json`) | Easy to share one job. | Partial-write and directory-scan cases with no matching benefit; nobody shares jobs yet. |
| **One versioned JSON file (chosen)** | Matches `TransferHistoryFile` (versioned envelope, atomic write, quarantine on corruption). Human-readable, diff-able, trivially backed up. | Whole-file rewrite on each save, which is trivial at this size. |

### Choice

`~/Library/Application Support/Nimbus/backups-v1.json`, pretty-printed with sorted keys:

```json
{
  "version": 1,
  "jobs": [
    {
      "id": "6F1C…",
      "name": "Documents to B2",
      "source": { "kind": "local", "path": "/Users/jonathan/Documents" },
      "destination": { "kind": "cloud", "remote": "b2", "path": "mac-backup/Documents" },
      "mode": "mirror",
      "excludes": [".DS_Store", "._*", "*.tmp"],
      "versions": { "enabled": true, "location": { "kind": "insideDestination" } },
      "removalLimit": 100,
      "schedule": { "kind": "daily", "hour": 2, "minute": 0 },
      "isPaused": false,
      "approvedFingerprint": "b5d1…",
      "approvedAt": "2026-11-08T21:05:00Z",
      "createdAt": "2026-11-08T21:00:00Z",
      "lastRun": {
        "startedAt": "2026-11-09T07:00:04Z", "finishedAt": "2026-11-09T07:03:41Z",
        "trigger": "scheduled", "outcome": "completed",
        "copied": 12, "replaced": 2, "removed": 1, "errors": 0, "bytes": 48213004
      }
    }
  ]
}
```

- `lastRun` lives on the job because transfer history is pruned (7 days by default) and the
  Backups screen must still say "Last backed up 3 weeks ago" after that.
- A corrupt file is moved aside (`backups-v1.corrupt-<uuid>.json`) and the screen shows an error
  with **Show in Finder**, never a silent empty list. An unknown `version` leaves the file untouched
  and the screen read-only.
- **Copy rclone Command** in each job's menu puts the equivalent CLI on the pasteboard, e.g.
  `rclone sync "/Users/jonathan/Documents" "b2:mac-backup/Documents" --exclude ".DS_Store" --exclude
  "/.nimbus-versions/**" --backup-dir "b2:mac-backup/Documents/.nimbus-versions/$(date
  +'%Y-%m-%d %H%M%S')" --max-delete 100`. Leaving Nimbus means pasting that into cron.

## Decision 4: versions

- **Default location:** inside the destination, in `.nimbus-versions/<run stamp>/`. It works for
  every destination, including a bucket or drive root where a sibling folder is impossible, and
  rclone requires the backup folder to be on the same remote anyway. Nimbus adds
  `/.nimbus-versions/**` to the job's exclude rules automatically; the editor shows it as a locked
  row so the exclusion isn't a surprise.
- **Other location:** any folder on the **same** cloud that doesn't overlap the destination. The
  editor offers only the destination's cloud, and the preview reports rclone's overlap error if
  one slips through.
- **Keep versions for:** Forever (default), 30 days, 90 days, 1 year. Pruning (phase 3) lists the
  top-level stamp folders and purges those whose **folder name** is older than the cut-off.
  Don't prune with `--min-age`: `--backup-dir` keeps each file's original modification time, so a
  two-year-old file removed today would be pruned at once.
- Turning versions off in mirror mode shows: "Files removed from the source will be deleted from
  <destination> for good."

## Decision 5: building on Copy & Sync instead of duplicating it

- **`LocationPicker`** replaces `PathPicker` in both screens. It's the same row with one more
  choice at the top of the menu: **This Mac…**, which opens an `NSOpenPanel` for a folder. A local
  endpoint shows the folder's icon and its Finder name. `FolderBrowserSheet` is unchanged and still
  browses clouds.
- **`TransferEndpoint`** (`.local(path)` / `.cloud(remote, path)`) replaces the string pair in
  `CopySyncView`, with an `fs` property that produces `"/Users/…"` or `"b2:mac-backup"`. It's the
  type `BackupJob` uses.
- **`BackupRequest`** builds RC parameters for both screens. `CopySyncViewModel.startOperation`
  goes through it with no excludes, no versions and no limit, which is today's behaviour.
- Copy Between Clouds gains two buttons: **Preview…**, the same preview sheet without the
  Approve buttons, and **Save as Backup…**, which opens the backup editor pre-filled.
- The `DestructiveCallout` moves to `Components/` because two screens now need it.

## Data model

```swift
enum TransferEndpoint: Codable, Hashable, Sendable {
    case local(path: String)                 // absolute POSIX path
    case cloud(remote: String, path: String) // path "" = cloud root
    var fs: String { get }                   // "/Users/x/Documents" or "b2:mac-backup"
    func appending(_ component: String) -> TransferEndpoint
}

struct BackupJob: Codable, Identifiable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case mirror, addOnly }
    struct Versions: Codable, Hashable, Sendable {
        enum Location: Codable, Hashable, Sendable { case insideDestination, custom(TransferEndpoint) }
        enum Keep: String, Codable, Sendable { case forever, days30, days90, year1 }
        var enabled: Bool
        var location: Location
        var keep: Keep
    }
    let id: UUID
    var name: String
    var source: TransferEndpoint
    var destination: TransferEndpoint
    var mode: Mode
    var excludes: [String]
    var versions: Versions
    var removalLimit: Int?          // mirror only; nil = no limit
    var schedule: BackupSchedule
    var isPaused: Bool
    var approvedFingerprint: String?
    var approvedAt: Date?           // anchors the first scheduled run; not fingerprinted
    let createdAt: Date
    var lastRun: BackupRunSummary?
}

enum BackupSchedule: Codable, Hashable, Sendable {
    case manual
    case hourly
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)   // Calendar weekday, 1 = Sunday
    func nextRun(after: Date, calendar: Calendar) -> Date?   // nil for .manual
}

struct BackupRunSummary: Codable, Hashable, Sendable {
    enum Trigger: String, Codable, Sendable { case manual, scheduled, catchUp }
    enum Outcome: Codable, Hashable, Sendable { case completed, failed(String), cancelled, limitHit }
    let startedAt: Date
    let finishedAt: Date
    let trigger: Trigger
    let outcome: Outcome
    let copied: Int, replaced: Int, removed: Int, errors: Int
    let bytes: Int64
}
```

`BackupRunSummary` counts come from the job's final `core/stats` (corrected after measuring rclone
1.76, see "Phase 1 as built"): `copied = transfers`, `removed = deletes`, and with versions
`replaced = renames − deletes`; without versions `replaced` is 0 (unknown).

### Changes to `TransferStore`

- `TransferOrigin` gains `.backup`.
- `Transfer` and `TransferRecord` gain `backupID: UUID?`, `title: String?` (the job name at run
  time, so history survives a rename or delete) and `summary: BackupRunSummary?`. They are
  optional, so version-1 history files still decode. A file holding backup records is written as
  version 2. An older build skips reading a version-2 file but overwrites it on its next save, so
  a downgrade loses transfer history; each job's `lastRun` survives in `backups-v1.json`.
- On completion of a `.backup` transfer, the store reads the job group's `core/stats` once before
  marking it finished, builds the summary, and calls an `onBackupFinished` hook that `BackupStore`
  uses to update `lastRun`.
- `TransferFilter` gains **Backups** (`origin == .backup`). `TransferRow` shows `title` when present
  ("Documents to B2") above today's src → dst line.
- `TransferNotificationService.request(for:)` gives backups their own copy:
  - success: "Backed up Documents to B2", body "12 files backed up, 1 moved to versions."
  - failure: "Backup Documents to B2 failed", body: the first line of the error through
    `NimbusError`.
  - limit hit: "Backup Documents to B2 stopped", body "It would have removed more than 100 files.
    Open Nimbus to preview it."
  Under the default **Failures only** mode, a limit-hit notifies (it counts as a failure).

## Screens

### Sidebar and navigation

- `SidebarSelection` gains `.backups`. The Tools section reads **Backups**
  (`clock.arrow.circlepath`) above **Copy Between Clouds**. `nextSelection` keeps `.backups` as
  is. `AppRouter.Request` gains `.backups(UUID?)` so a notification or the menu bar can open the
  screen on a job.
- `AppCommands` gets **New Backup…** (⇧⌘B).

### Backups screen (`Views/Backups/BackupsView.swift`)

- **Toolbar:** title "Backups", **New Backup…** (prominent).
- **Empty state:** `EmptyState` with "Back up a folder automatically", "Copy a folder on this Mac or
  in one cloud to another cloud on a schedule. You see what will change before anything
  runs.", **New Backup…**.
- **One row per job:**
  - Leading: the destination's `ProviderBadge`, or a Mac icon for a local destination.
  - Name, and "Documents → B2 › mac-backup/Documents" in secondary text.
  - Status sentence, first match wins:

    | State | Sentence | Tint |
    |---|---|---|
    | Running | "Backing up… 45%, 3 min left" plus a `ProgressMeter` | info |
    | Queued | "Waiting for another backup to finish" | secondary |
    | Approval missing | "Preview needed before it can run" | warning |
    | Paused | "Paused" | secondary |
    | Last run failed | "Failed <relative>: <short reason>" | error |
    | Last run hit the limit | "Stopped <relative>: would remove more than N files" | warning |
    | Last run completed | "Backed up <relative>, N files" | ok |
    | Never run | "Not run yet" | secondary |

  - Schedule line: "Every day at 2:00 AM · next tomorrow at 2:00 AM", or "Manual".
  - Trailing: **Back Up Now** (or **Preview…** when approval is missing, or **Stop** while
    running).
  - Context menu: Edit…, Preview…, Back Up Now, Pause/Resume Schedule, Show Versions, Show
    History (opens the destination cloud's Transfers tab with the Backups filter; for a local
    destination, the source cloud's), Copy rclone Command, Duplicate, Delete….
  - Delete asks "Delete the backup “Documents to B2”? Files already backed up stay where they
    are."
- **Footer** (only while a job has a schedule and Open at Login is off): "Scheduled backups run
  while Nimbus is open, including from the menu bar." plus the **Open at Login** toggle.

### Editor sheet (`BackupEditorSheet`, 600 × 640, `SheetChrome`)

Form sections, top to bottom:

1. **Name**, defaulting to "<source folder> to <destination cloud>".
2. **Back up:** `LocationPicker` (source). **To:** `LocationPicker` (destination). Validation: the
   two must differ, and neither may contain the other on the same cloud ("The destination is
   inside the source, so each run would back up the last one.").
3. **Mode**, a segmented picker:
   - **Mirror:** "The destination matches the source. Files you delete here are removed there
     too." (With versions on: "…are moved to versions there.")
   - **Add only:** "New and changed files are copied. Nothing is ever removed from the
     destination."
4. **Versions:** the "Keep replaced and removed files" toggle (on by default), location (Inside the
   destination / Choose folder…), and Keep for (Forever / 30 days / 90 days / 1 year; phase 3).
5. **Skip:** the exclude list: one pattern per row, + and − buttons, presets in a menu (Mac junk:
   `.DS_Store`, `._*`, `.Trash/**`, `.Spotlight-V100/**`; Temporary: `*.tmp`, `~$*`; Developer:
   `node_modules/**`, `.build/**`, `DerivedData/**`). The locked `/.nimbus-versions/**` row appears
   when versions are inside the destination. Help text: "* matches within a name, ** matches across
   folders, a leading / means the top of the backed-up folder." New jobs start with the Mac junk
   preset.
6. **Safety** (mirror only): "Stop a run that would remove more than [100] files", with a toggle
   and a number field.
7. **Schedule:** a kind picker plus a time and weekday as needed, and the Open at Login note from
   decision 1.

Footer buttons: **Cancel**, and **Save and Preview…** (prominent). Saving a job whose fingerprint is
unchanged (only name or schedule edited) shows **Save** instead and doesn't re-preview.

### Preview sheet (`BackupPreviewSheet`, 640 × 560)

- **While running:** a spinner, "Checking what would change…", and "N items checked" from
  `listed`, plus **Stop**.
- **Result header:** one sentence per mode.
  - Mirror: "12 files will be copied, 2 replaced and 1 removed." With versions on, a second line:
    "Replaced and removed files are kept in .nimbus-versions."
  - Add only: "12 files will be copied and 2 replaced."
  - Nothing to do: "Everything is already backed up."
  - Approximate size: "About 48 MB to upload" (or "to copy" for local destinations) from
    `totalBytes`, labelled approximate because it includes moves into versions.
- **Three tabs** (`Picker(.segmented)`), Copy (N) / Replace (N) / Remove (N), each a `List` of
  paths, virtualized, monospaced-digit counts. Remove is hidden for add-only.
- **Warnings:** the removal-limit callout described in decision 2, and errors listed first in
  error tint.
- **Buttons:** **Cancel**, **Approve**, and **Approve and Back Up Now** (prominent). From Copy
  Between Clouds the sheet shows only **Done** and **Start <Copy/Sync>**.

### Home, menu bar, Transfers

- Home's recent activity line for a backup reads "Backed up Documents to B2" or "Backup Documents
  to B2 failed".
- Home "Worth a look" (phase 3): "Documents to B2 hasn't run in 3 days" when a scheduled job is
  more than three slots overdue, and "Documents to B2 failed last night" with **Open Backups**.
- The menu bar and `CloudSummaryBuilder` treat a running backup like any active transfer, so the
  busy glyph and "Uploading N items" need no change.
- The companion's gear menu gains **Backups…**.

## Where the code goes

| File | Kind | Purpose |
|---|---|---|
| `RcloneKit/Sources/RcloneKit/Sync.swift` | modify | `SyncRequest` (operation, srcFs, dstFs, config overlay, excludes, report flags) and `startSync(_:) -> Int`. `copy`/`sync` keep their signatures and call it. |
| `RcloneKit/Sources/RcloneKit/Models.swift` | modify | `SyncReport`; `Job.output: SyncReport?` decoded with `try?`, so other jobs' outputs don't break decoding. `StatsResponse` gains `renames`, `listed`. |
| `State/TransferEndpoint.swift` | new | Endpoint enum, `fs`, containment check. |
| `State/BackupJob.swift` | new | `BackupJob`, `BackupSchedule`, `BackupRunSummary`, fingerprint. |
| `State/BackupRequest.swift` | new | Pure builder: job + dry-run flag + stamp → `SyncRequest`, and the CLI string. |
| `State/BackupsFile.swift` | new | Versioned file I/O, same shape as `TransferHistoryFile`. |
| `State/BackupStore.swift` | new | `@Observable @MainActor`: jobs, CRUD, approval, `lastRun` updates, persistence. |
| `Services/BackupRunner.swift` | new | FIFO queue, power assertion, starts runs through `TransferStore`, stop, quit guard query. |
| `Services/BackupPreviewer.swift` | new | Dry run, polling, `BackupPreview`. |
| `Services/BackupScheduler.swift` | new | Planner (pure `dueJobs(now:)` / `nextWake(now:)`) plus the timer and wake observers. |
| `Views/Backups/*` | new | `BackupsView`, `BackupRow`, `BackupEditorSheet`, `BackupPreviewSheet`, `ExcludeListEditor`. |
| `Views/CopySync/LocationPicker.swift` | replaces `PathPicker.swift` | Adds This Mac. |
| `Components/DestructiveCallout.swift` | moved | From `CopySyncView`. |
| `State/TransferStore.swift`, `TransferHistoryFile.swift`, `Services/TransferNotificationService.swift`, `Views/Transfers/*` | modify | `.backup` origin, new fields, filter, row title, notification copy. |
| `NimbusApp.swift`, `AppDelegate.swift`, `Views/Sidebar.swift`, `SidebarSelection.swift`, `AppRouter.swift`, `AppCommands.swift`, `ContentView.swift` | modify | Wiring, quit guard, navigation. |

## Phasing

Each phase is its own PR, works on its own, and leaves `main` shippable.

1. **Saved backups, preview, Back Up Now.** RcloneKit request and report; endpoint; job model;
   file; store; request builder and CLI string; previewer; runner without a schedule; the
   `TransferStore` changes; Backups screen, editor and preview sheets; Copy Between Clouds gets
   This Mac, Preview… and Save as Backup…. The schedule picker is present but limited to Manual.
2. **Schedule.** `BackupScheduler`, catch-up, wake and clock observers, power assertion, quit
   guard, backup notifications, Open at Login nudge, `AppRouter.backups`.
3. **Versions upkeep and surfaces.** Keep-for pruning, Show Versions, Home's activity wording and
   "Worth a look" items, companion menu item.

## Exit gates

- **Unit tests:**
  - `BackupSchedule.nextRun` for hourly, daily and weekly, across a DST spring-forward and
    fall-back day in `America/New_York`, and the time-zone change.
  - The scheduler planner: a missed slot runs once, a paused job never runs, an unapproved job
    never runs, a running or queued job isn't queued twice.
  - `BackupRequest`: mirror vs add-only, the versions-inside exclusion, the stamp in the backup
    dir, report flags only on dry runs, no `missingOnSrc` for add-only, `MaxDelete` only for
    mirror. Plus a CLI-string snapshot for one job of each shape.
  - The fingerprint changes on every fingerprinted field and not on name or schedule.
  - `BackupsFile`: round-trip, corrupt → quarantine, unknown version → read-only.
  - `TransferHistoryFile` v1 → v2 migration keeps records. The `.backup` origin round-trips.
  - Notification copy for success, failure and limit hit under each notification mode.
- **RcloneKit tests** assert on the **captured request body** (the Tolaria contract gotcha):
  `_config.DryRun`, `_config.BackupDir`, `_config.MaxDelete`, `_filter.ExcludeRule`, the report
  flags, and `job/status` output decoding for a sync job (with a report) and a non-sync job (no
  report).
- **Live check against `rclone serve s3` or a local-to-local pair,** recorded in the spec's
  as-built section:
  - A preview lists exactly the copy, replace and remove sets of the scratch tree above.
  - After **Approve and Back Up Now**, the destination matches and versions hold the replaced and
    removed files.
  - An empty source with limit 2 previews as "would remove more than 2", and a forced run stops
    with the limit-hit notification.
  - A daily job set two minutes ahead runs on time. Putting the Mac to sleep across a slot runs it
    once on wake.
  - Quit during a run asks first, and the run counts as missed on relaunch.
- **RenderPreview** of `BackupsView` (empty, one of each status row), `BackupEditorSheet` (mirror
  with versions, add-only), and `BackupPreviewSheet` (running, result, nothing to do, limit
  warning, errors), in light and dark.
- VoiceOver reads each backup row as one sentence: name, status, schedule.
- Zero new compiler warnings, no `.system(size:)`, no new dependencies.
- The live check runs in a user account with no real Nimbus File Provider domains, or against a
  config that contains all of them (the `cleanupStaleDomains` gotcha from the Home spec).

## Risks

- **Large previews.** The first preview of a big folder to an empty destination returns every
  path in `missingOnDst`. 200,000 paths is roughly 10–20 MB of JSON once, which is acceptable.
  The sheet uses a lazy `List`; if decoding stalls the main actor, decode off-main in the
  previewer.
- **The removal limit is a circuit breaker, not a gate.** It still removes up to N files before
  stopping. With versions on, those N are in versions. The spec says so in the editor's help
  text.
- **TCC prompts.** Backing up `~/Documents` or `~/Desktop` triggers macOS's "Nimbus would like to
  access files in your Documents folder" prompt the first time rclone reads it. The required
  preview runs while the user is at the Mac, so the prompt appears then and not at 2 AM.
- **Destination quota.** A backup that fills the destination fails with the provider's error.
  Home's existing "almost full" suggestion covers the warning side.

## Decided questions (2026-11-08)

These were open in the first draft. The user left the calls to the session that ran the
competitive research, and it decided them as follows:

1. **Default mode for a new backup: Mirror with versions on.** The versions folder makes
   removals recoverable. Add only would grow the destination forever.
2. **Default removal limit: 100 files, adjustable per job.** There's no percentage option, since
   rclone would need a pre-run listing for one. The required preview before the first run makes
   a count limit enough for v1.
3. **Scheduling runs in the app only (decision 1, option A) for v1.** Nimbus already stays in the
   menu bar and opens at login, and missed runs catch up once. Option D (a helper that owns the
   daemon) is left for later.

## Phase 1 as built (2026-11-08, `feat/backups-phase1`)

Where the build differs from the sections above, the build wins.

- **A preview that hits the removal limit can't be approved.** The real run would stop at the
  same limit, so the sheet shows the limit callout and **Edit Backup…** instead. The second
  confirmation covers more than 100 removals (`BackupPreview.largeRemovalThreshold`) when no
  limit, or a higher one, allows them. A preview with read errors also offers only **Edit
  Backup…**.
- **Run counts, measured on rclone 1.76.** `deletes` counts files that left the destination.
  With a backup dir, `renames` counts every move into it, replaced plus removed (local mirror
  of new + changed + destination-only: transfers 2, deletes 1, renames 2). So `removed =
  deletes` and `replaced = renames − deletes`. The data-model paragraph above is corrected.
- **Pre-existing bug fixed in RcloneKit.** Since 4ba0fc0, `RcloneClient` treated any 200 body
  with an `error` key as an RC error. Every `job/status` body has one (`""` on success), so
  `jobStatus` always threw and `TransferStore` never marked a transfer finished. A 200 body is
  now an error only with rclone's envelope (`path` or `status`).
- **No schedule section in phase 1.** The editor has none (a one-choice picker is noise).
  ⇧⌘B opens the Backups screen. New Backup… is its toolbar button.
- **Small copy additions:** a completed run with no files reads "Backed up <when>, no
  changes"; a cancelled run reads "Stopped <when>"; queued rows offer **Cancel**. Friendly
  errors: "directory not found" becomes "The source folder isn't available. Is the drive
  connected?", and the backup-dir overlap error names the versions folder.
- **History file:** version 2 only when a record has backup data, so an older Nimbus keeps
  reading backup-free history. (An older Nimbus overwrites a version-2 file on its next save.)
- **From the final review:**
  - A dry run that comes back without a report fails ("This version of rclone can't list what a
    backup would change…") instead of reading as "Everything is already backed up". rclone 1.76
    returns every requested list, empty when nothing would change.
  - The removal limit is recognised by `core/stats.lastError` = "--max-delete threshold
    reached". Other delete failures (permissions, object lock) share the job error "failed to
    delete N files" and now show their real reason instead of "would remove more than N files".
  - A run rclone no longer knows ("job not found": expired, or a new daemon) ends as failed, and
    every daemon (re)connect ends transfers left from the previous process. The backup queue
    can't get stuck behind a run that will never report back.
- **Copy Between Clouds' title** now matches the sidebar.

### Live results

`BackupLiveTests` (opt-in: `TEST_RUNNER_NIMBUS_LIVE_RCLONE=/opt/homebrew/bin/rclone`) drives
the previewer, runner and `TransferStore` against a real `rclone rcd` (1.76) on the scratch tree:

| Check | Result |
|---|---|
| Preview lists +`new.txt`, *`sub/changed.txt`, −`onlydst.txt`; `skip.log` excluded | pass |
| The dry run leaves the destination untouched | pass |
| Approve and Back Up Now: destination matches; `.nimbus-versions/<stamp>/` has `onlydst.txt` and the old `sub/changed.txt` | pass |
| Run summary: copied 2, replaced 1, removed 1 | pass |
| Second preview: "Everything is already backed up" (versions folder untouched) | pass |
| Empty source, limit 2: preview reports `limitHit`, can't be approved, nothing removed | pass |

Not verified: the full GUI flow in the running app. Launching a second Nimbus on this Mac
would run its stale-daemon cleanup against the installed app's rclone. Screens were checked
with RenderPreview (every row status, editor in both modes, every preview state, light and
dark).
