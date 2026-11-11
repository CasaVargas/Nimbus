# Remote changes reach Finder faster (#76)

Date: 2026-11-11
Status: implemented (live Finder check pending on a signed build)

## Problem

A change made elsewhere reaches Finder within about ten minutes (0.10.1
known issue). Official clients are close to instant. The ten minutes is
`CloudMonitor.periodicInterval`: each refresh signals the working set, and
the extension re-lists **every** folder it knows about
(`2026-11-08-finder-remote-changes-design.md`). Signalling more often would
re-list every known folder more often, and that is the "polling every cloud
harder" the issue rules out.

## Constraint that shapes the design

Nimbus's extension is an `NSFileProviderReplicatedExtension`. The system
only accepts signals for `.workingSet`, and it never asks a folder's own
enumerator for changes after the first listing. Two ideas from triage don't
work because of that:

- *Signal each live folder enumerator.* Those signals are ignored.
- *A "live enumerator" means the folder is open.* The system lists a folder
  into its replica once and then drops the enumerator. Finder showing the
  folder later creates nothing in the extension.

So all change detection still runs from the working set's
`enumerateChanges`. What changes is **which folders** a pass re-lists, and
**how often** passes run.

## Design

### Two scan scopes

- **Full scan.** Same as today: every known folder. Runs when the last full
  scan is 10 minutes old, or when the app asks for one (daemon connect,
  the periodic `CloudMonitor` refresh, ⌘R in a browser).
- **Hot scan.** Only the cloud's *hot folders* (below), listed four at a
  time. Runs when it's due on the backoff schedule.
- **Nothing.** Neither is due: the pass reports no changes and makes no
  rclone calls. With no hot folders a hot scan is never due.

The app signals every working set every **30 seconds** (`RemoteChangeTicker`).
A signal costs no network. The extension decides the scope from its own
persisted state, so the decision survives the extension being relaunched.

### Hot folders ("open or pinned")

The extension can't see what Finder shows, so "open" means **recently
active**. A known folder is hot when, in the last **30 minutes**:

- the system listed it (`enumerateItems`), or
- a file in it was opened (`fetchContents`), or
- something in it was created, changed or deleted from this Mac.

A folder is also hot, with no time limit, when it is **pinned** (Keep
Downloaded) or holds a pinned file.

Only folders with a listing snapshot count. At most **50** hot folders are
scanned per cloud, most recently active first (pinned folders go first).

### Backoff (per cloud)

- A hot scan becomes due 30 s after the previous scan.
- A hot scan that finds nothing doubles the wait, up to **5 minutes**.
- A scan that finds a change, or new activity in a folder after the last
  scan, resets the wait to 30 s.
- A full scan also counts as a hot scan for scheduling.

Worst case for a folder the user is working in: about one minute (one
tick plus one wait). For a folder left alone for 30 minutes: the next full
scan, as today.

### Where it lives

- `Shared/RemoteChangeCadence.swift` — pure policy: the hot-folder map
  (touch, expiry, pinned, cap), the scheduling state, the scope decision
  and the backoff. Codable, unit-tested from `NimbusTests`.
- `Shared/RemoteChangeCadence.swift` also has `FullScanRequest`, the
  file the app writes (`FileProviderSync/<cloud>/full-scan-requested`)
  before signalling when it wants a full scan.
- `RemoteChangeWalk.visitAll` (Shared) — lists a flat set of folders at a
  fixed width; the hot scan uses it.
- Extension: `HotFolderStore` persists the cadence state per cloud
  (`FileProviderSync/<cloud>/cadence.json`), with in-memory throttling so a
  burst of opens writes once a minute at most. `RemoteChangeScanner` gets a
  `scan(containers:)` for the hot scope. `WorkingSetEnumerator` asks the
  policy which scope to run.
- App: `CloudMonitor`'s refresh requests a full scan before signalling;
  ⌘R in the browser does too. `RemoteChangeTicker` sends the 30 s signal
  while Nimbus runs.

## Cost

A cloud nobody is using: one full scan every 10 minutes, as today. A cloud
with a few hot folders: their listings every 30 s while changes keep
coming, falling to every 5 minutes when they stop, and none once the folders
cool off. Listings are capped at four in flight per cloud.

## Not in scope

- rclone `ChangeNotify` (Drive, OneDrive, Dropbox push). The RC API still
  doesn't expose it outside a VFS mount. It would mean a long-running
  `vfs` per cloud just to get notifications; worth a spike on its own.
- Knowing what Finder shows. Recent activity is the proxy.

## Verification

- Unit tests (`RemoteChangeCadenceTests`): scope decision (first pass,
  requested, age, hot due, nothing due, no hot folders), backoff doubles,
  caps and resets, activity resets the wait, hot-folder expiry, pinned
  folders don't expire, the cap keeps the most recent, `visitAll` never
  exceeds its width, full-scan request round trip.
- Build: `Nimbus` scheme, Swift 6 strict concurrency.
- Live (signed build): edit a file on the server in a folder just opened in
  Finder; it appears within about a minute.
