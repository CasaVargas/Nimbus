# Finder picks up server-side changes

Date: 2026-11-08
Status: implemented

## Problem

Files and folders that change on the server (added, renamed, deleted, or
edited by another client) never reach `~/Library/CloudStorage/Nimbus-<cloud>/`.
Relaunching the app or reopening the folder in Finder doesn't help. Only a
forced `reimportItems(below: .rootContainer)` brought them in, and that is a
full re-import.

Cause: Nimbus's extension is an `NSFileProviderReplicatedExtension`. For a
replicated extension the system only asks for changes through the
**working set**. It ignores `signalEnumerator(for: .rootContainer)` and never
calls `enumerateChanges` on a folder's enumerator after the first listing.
`FileProviderBridge.signalAllDomains()` signalled the root (which did
nothing) and the working set. The working-set enumerator only reported Keep
Downloaded pin changes, so remote changes had no way in.

## Design

### Extension: the working set reports remote changes

`WorkingSetEnumerator.enumerateChanges` now does two things and reports
both in one batch:

1. **Pin changes**, as before, from `PinStore`'s change log.
2. **A remote scan** of every folder the system already knows about:
   - *Known folders* are the folders that have a listing snapshot
     (`SyncSnapshotStore`, written whenever the system lists a folder).
     They are found by walking from the root snapshot: each snapshot's
     folder children that also have a snapshot are known. This needs no new
     index and works with snapshots written by earlier builds. A deleted
     folder drops out of the walk on its own.
   - Each known folder is listed again through rclone and diffed against
     its snapshot. New or changed entries (name, size, mod time, keep
     state) become `didUpdate`. Missing entries become
     `didDeleteItems`. The new listing replaces the snapshot.
   - When a folder in a diff was deleted, its own snapshot is removed.
   - Listings run four at a time, level by level, using the fresh child
     lists so a folder created and opened since the last scan is included.
   - A folder whose listing fails is skipped this pass and its snapshot is
     kept. If it's really gone, its parent's diff reports the deletion.

A rename on the server is a delete plus an add (that's what S3 and most
rclone backends report), so Finder sees the old name go and the new name
appear.

### Working-set sync anchor

The anchor is now 16 bytes: the pin change-log sequence and a per-cloud
**remote generation** that goes up whenever a scan finds changes. Both are
little-endian Int64. An 8-byte anchor from an earlier build decodes as
`(sequence, generation 0)`, so existing replicas don't expire. The
generation is stored next to the snapshots
(`FileProviderSync/<cloud>/remote-generation`).

Snapshots are state, not a log: a scan reports everything that differs from
the last persisted listing, whatever anchor the system asks from. An
expired pin log still returns `syncAnchorExpired`, as before.

### Pure logic lives in `Shared/`

The diff, the "which children are folders to walk" step and the anchor
encoding are pure functions in `Nimbus/Shared/RemoteChangeDiff.swift`. They
compile into both the app (so `NimbusTests` can cover them) and the
extension. `SyncedItemRecord` and `ContainerSnapshot` move there too.
`SyncSnapshotStore.diffAndPersist` uses the same diff.

### App: when to signal

The only signal that matters is `.workingSet`. The app sends it:

- after every `CloudMonitor` refresh (daemon connect, every 10 minutes,
  cloud list changes, companion opened with stale data), for every
  registered domain;
- when the user presses ⌘R (Refresh) in a cloud's browser, for that cloud.

`signalAllDomains()` stops signalling `.rootContainer`.

## Cost

One rclone listing per known folder per refresh. With the 10-minute cadence
and a few dozen opened folders that's a few thousand list calls a day,
cheap for every provider Nimbus targets. Folders only become known when the
user opens them in Finder.

## Not in scope

- rclone change notifications (`ChangeNotify`, Drive/OneDrive/Dropbox).
  The RC API doesn't expose them outside a VFS mount. The scan works for
  every backend; push notifications can shorten latency later.
- Pruning snapshots of folders not opened in a long time.
- Folding size into the content version (edits that keep the mod time
  still diff as changed, but the content version only tracks mod time).

## Verification

- Unit tests (`RemoteChangeDiffTests`): diff (added, changed, deleted,
  unchanged, first listing), folder-children selection, deleted-folder
  selection, anchor round trip and legacy decoding.
- Live: on a local `rclone serve s3` cloud, add, rename and delete a file
  on the server; each shows up in Finder after one refresh (⌘R in the
  browser or the next CloudMonitor refresh), with no re-import.

### Live result (2026-11-08, `s3test` on `rclone serve s3`)

Refresh = relaunching Nimbus (the daemon-connect refresh). Each change
showed in `~/Library/CloudStorage/Nimbus-s3test/` after one refresh:

| Change on the server | Scan log | Finder |
|---|---|---|
| Existing backlog (new bucket `wallpapers`, 2 files in `pics`, `shared/thumbs`) | 5 updated | bucket and files appear |
| Add `pics/nimbus-live-check.txt` | 2 updated (file + `pics` entry) | file appears |
| Rename it | 2 updated, 1 deleted | old name gone, new name appears |
| Append to it | 1 updated | new size; reading it gets the new content |
| Delete it | 1 updated, 1 deleted | file gone |
| Nothing | 0 updated | unchanged |

With the S3 server down, the scan skipped the timed-out folders and reported
nothing, as designed. `shared/thumbs` reached the system but waited on
`parentCreation`: `shared` itself hadn't finished importing on disk in that
domain, which predates this change.
