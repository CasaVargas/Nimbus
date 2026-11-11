# Compare Two Folders — Design

**Date:** 2026-11-11
**Status:** Approved 2026-11-11 (Jon): a separate Compare sidebar item, read-only in v1.
**Issue:** #73
**Builds on:** `Views/CopySync/` (`LocationPicker`, `FolderBrowserSheet`, the From/To wells),
`Services/BackupPreviewer.swift` (the polled, cancellable rclone job pattern).

## Why

"Did my copy get everything?" and "what's different between my Drive and my Mac folder?" have
no answer in Nimbus today short of browsing both sides by hand. rclone's `check` answers it in
one call. Competitors (RcloneView) ship a compare view.

## Decision

1. **Where:** its own sidebar item, **Compare Folders**, under Tools after Copy Between Clouds,
   with its own screen. Not a mode on Copy Between Clouds, which stays a simple form.
2. **Read-only in v1.** No "copy missing" or "sync differing" buttons. Compare never writes,
   so it needs no `TransferStore` entry and no destructive confirmation. Follow-up actions are a
   later issue; the results model keeps the paths so they can be added without reshaping it.

## Screen

- **Header:** page title "Compare two folders", a lead line, and a `GlassSegmented` for the
  method: **Checksum** (default: size plus hash where both sides share one) or **Size only**
  (fast; ignores content).
- **Wells:** two glass wells side by side, **A** and **B**, each with the same place summary
  (logo/icon, name, path) and a `LocationPicker(layout: .stacked)` as Copy Between Clouds.
  Either side can be any cloud folder or a folder on this Mac. The connector between them is
  a two-way arrow (`arrow.left.arrow.right`), not a one-way arrow: compare has no direction.
- **Run row:** **Compare** primary pill (⏎). While running: a spinner, "Comparing… N files
  checked", and **Stop**. Compare is disabled until both sides are chosen and differ.
- **Results:** a row of glass tiles with counts (Different, Only in A, Only in B, Same, plus
  Couldn't Read only when rclone reported errors). The tiles pick which group the list below
  shows, one group at a time, so a 50,000-file Same list never pushes the differences off
  screen. The first non-empty group, in that order, is selected after a run. An empty group shows
  "None". When nothing differs, a "These folders match" banner sits above the tiles. Paths are
  selectable text.
- **Stale results:** changing either place or the method clears the result.
- **No common hash:** when rclone reports `hashType` `none` (or empty) for a Checksum compare,
  a callout says sizes were compared but content wasn't, because the two places share no
  checksum type.
- **Errors:** a run that fails (bad remote, network) shows the `EmptyState` banner used by Copy
  Between Clouds with rclone's message made friendly.

## rclone call

`operations/check`, started with `_async: true` and polled with `job/status`, the same loop as
`BackupPreviewer`.

```json
{ "srcFs": "<A fs>", "dstFs": "<B fs>", "combined": true, "_async": true,
  "_config": { "SizeOnly": true } }   // _config only for Size only
```

Verified on rclone 1.76 (2026-11-11):

- The job's `output` holds `combined`, `missingOnSrc`, `missingOnDst`, `differ`, `error`,
  `hashType`, `status` and `success`. The **job** succeeds (`success: true`) even when the
  folders differ; the **report's** `success` is false and `status` reads "3 differences found".
  So differences are never treated as a failure.
- `combined` lines are `<sign> <path>`: `=` same, `*` differ, `+` only in A (missing on B),
  `-` only in B (missing on A), `!` error. Parsing `combined` gives all five groups from one
  list, including Same, which the other lists don't carry.
- A missing folder on one side is not an error; everything reads as only on the other side.
  An unknown remote fails the call (`didn't find section in config file`).

**Cancel:** Stop calls `job/stop` and returns the screen to idle with no results. Leaving the
screen (the view's task is cancelled) stops the job too.

**Progress:** the `job/<id>` group's `core/stats` `checks` count, shown as "N files checked".

## Code

| Piece | Where |
|-------|-------|
| `CheckRequest`, `CheckReport`, `CheckJobStatus`, `RcloneClient.startCheck`, `checkStatus` | `RcloneKit/Sources/RcloneKit/Check.swift` |
| `CompareResult` (groups parsed from `combined`), `CompareViewModel` (`idle → running → finished / failed`), `CompareRcloneClient` protocol | `Nimbus/Nimbus/ViewModels/CompareViewModel.swift` |
| `CompareView`, `CompareResultsView`; `EndpointWell` + `WellConnector` extracted from Copy Between Clouds and shared | `Nimbus/Nimbus/Views/Compare/`, `Views/CopySync/EndpointWell.swift` |
| `.compare` sidebar case, menu command (⇧⌘D; ⇧⌘5 is the system screenshot shortcut), screen routing | `SidebarSelection.swift`, `Sidebar.swift`, `ContentView.swift`, `AppCommands.swift` |

`Job` keeps decoding `output` as a `SyncReport`; a check job is read through its own
`CheckJobStatus` so the two shapes don't mix.

## Tests

- RcloneKit: the request body (`srcFs`, `dstFs`, `combined`, `_async`, `_config.SizeOnly` only
  for Size only); decoding a captured 1.76 job status with differences, an all-match one, and
  empty lists.
- `CompareResult` parsing of every sign, paths with spaces, and unknown lines ignored.
- `CompareViewModel`: idle → running → finished, a failed start, a failed job, stop returns to
  idle and calls `job/stop`, and the no-common-hash flag.
- `nextSelection` keeps `.compare`.

## Out of scope (v1)

Copy or sync actions on results, filters/excludes, one-way compare, download (byte-by-byte)
compare, exporting the report, and comparing more than two folders.
