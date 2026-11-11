# Cloud files findable from Spotlight (#66)

Date: 2026-11-11
Status: implemented

## Question

Can Spotlight find files in a Nimbus cloud that aren't downloaded, on a
third-party replicated File Provider (macOS 15 and later)?

## Spike result (2026-11-11, macOS 27.2, release build 0.10.1)

**Yes.** Spotlight already indexes dataless (not downloaded) items under
`~/Library/CloudStorage/Nimbus-<cloud>/`, but only some of them.

| Domain | Files listed at the root | Indexed (`mdfind -onlyin <domain> -name .`) |
|---|---|---|
| Nimbus-MCS | 91 (89 `compressed,dataless`) | 10, all `compressed,dataless` |
| Nimbus-GoogleDrive | 88 entries | 11 |
| Nimbus-OneDrive | 5 entries | 0 |

`mdls` on an unindexed dataless file reads its name fine; the file just
isn't in the index. Every indexed item had a `kMDItemLastUsedDate` (it had
been opened or previewed); the unindexed ones had none.

Apple's File Provider docs give the rule: "The system indexes the items the
working set enumerator provides so they are searchable", and it updates the
index "whenever you notify it of changes to the working set".

Nimbus's working-set enumerator has reported changes since the 2026-11-08 work
(`2026-11-08-finder-remote-changes-design.md`), but its `enumerateItems`
returned an empty list. So an item reached the index only if something
reported it as a working-set *change* (a pin, a server-side edit) or the
user touched it. A file that was listed once and never changed stayed out.

## Mechanism

**Chosen: the File Provider working set.** `WorkingSetEnumerator.enumerateItems`
lists every item in every folder the system has listed, read from the
per-folder snapshots `SyncSnapshotStore` already keeps. No network call:
the snapshots are exactly what the system knows about. Deletes and renames
already flow through the working set's change path (`RemoteChangeScanner`),
which the system applies to the index.

**Rejected: Core Spotlight (`CSSearchableIndex`) from the app.** It would
duplicate what the system does for free, needs an `NSUserActivity` handoff
to open a result, would show results as Nimbus app entries rather than
files, and would drift from Finder whenever the two disagree.

## Design

- `Shared/RemoteChangeDiff.swift`: `WorkingSetListing.collect(root:snapshot:)`
  walks known folders from the root, snapshot only, and returns each entry
  with its parent. Folders without a snapshot are listed but not entered
  (the system hasn't listed them either). Cycles and duplicates are skipped.
- `WorkingSetEnumerator.enumerateItems` pages that list out, 500 items a page.
- **Existing installs.** The system enumerates the working set's items only
  on first use or after `syncAnchorExpired`. The anchor gains a format
  number (a third Int64). An anchor from an earlier build (8 or 16 bytes)
  decodes as format 0; `enumerateChanges` answers it with
  `syncAnchorExpired` once, so the system re-lists the working set and
  indexes everything. New anchors are 24 bytes, format 1.

## Not in scope

- Folders never opened in Finder or the browser aren't indexed: Nimbus
  doesn't crawl the whole cloud. The issue asks for "at least once the
  folder has been listed".
- Content (full-text) search of non-downloaded files: Spotlight only has
  the name and metadata.

## Verification

- Unit: `WorkingSetListingTests` (walk, parents, unknown folders, cycles),
  anchor round trip with format, legacy anchors decode as format 0.
- Live: install the build, relaunch Nimbus, wait for the working-set
  re-list, then `mdfind -onlyin ~/Library/CloudStorage/Nimbus-<cloud> -name .`
  counts every listed file; `mdfind -name <file>` finds a dataless one.
