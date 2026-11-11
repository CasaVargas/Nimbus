# Cloud files findable from Spotlight (#66)

Date: 2026-11-11
Status: spike done; working-set approach not confirmed live, mechanism open

## Question

Can Spotlight find files in a Nimbus cloud that aren't downloaded, on a
third-party replicated File Provider (macOS 15 and later)?

## Spike result (2026-11-11, macOS 27.2)

**Feasible: Spotlight does index dataless (not downloaded) Nimbus items.**
`mdfind -name cmtrace` returns `~/Library/CloudStorage/Nimbus-MCS/cmtrace.exe`,
a `compressed,dataless` file.

**What drives the indexing is still unproven.** The first pass counted
indexed items with `mdfind -onlyin <domain> -name .` and got 10 of 91. That
query undercounts: it misses files that the exact query
`kMDItemFSName == "<name>"` finds in the same scope. So the "before" numbers
are wrong, and the working-set hypothesis below rested on them.

Measured with the PR build installed, checking each top-level entry by exact
name (plain bash: the zsh `ls` alias here is `eza --icons`, which corrupts
filenames in loops):

| Domain | Found | Missing |
|---|---|---|
| Nimbus-MCS | 119 | 0 |
| Nimbus-GoogleDrive | 67 | 20: 4 hidden dotfiles, plus 16 visible items |
| Nimbus-OneDrive | 3 | 1 (`.DS_Store`) |

The 16 visible Google Drive items were in the working-set listing the
system received, and they were still unindexed after 11 minutes.

**Folders opened for the first time:**

- `Fonts`, listed under the PR build (no working-set report): 0 of 4
  entries indexed after 7 minutes.
- `Software Licenses` and `iPhone Apps`, listed under a build that reports
  first-listed folders' entries through working-set changes (the log
  confirmed 3 reported): 0 of 3 indexed after 7 minutes.

Neither listing through the working set nor reporting entries as changes
indexed anything within minutes. Apple's docs say the system indexes
working-set items, but I couldn't confirm that here.

### Hypothesis that was tested

Apple's File Provider docs say: "The system indexes the items the working
set enumerator provides so they are searchable." Nimbus's working-set
`enumerateItems` returned an empty list. The PR made it list every
snapshotted item and expired old anchors so domains re-list. The re-list
ran (logs: MCS 119 items, Google Drive 95, OneDrive 3), but the live
results above don't show it changing what Spotlight finds.

### Candidate: `NSFileProviderSearching`

`NSFileProviderSearching` plus `NSFileProviderDomain.supportsStringSearchRequest`
has the system's search UI ask the extension to search the cloud
(`searchEnumerator(for:)` returns results for a query string). Apple's docs
say you don't need it "if you only want to expose the contents of the
working set to system search". That makes it the route for files beyond the
working set, and it covers files in folders never opened. The cancellable
per-remote name search from #65 (RcloneKit) is the backend it needs. Before
building on it, check its OS availability and whether `mdfind` or only the
Spotlight UI uses it.

### Spike: `NSFileProviderSearching` (2026-11-11)

Built on this branch: `FileProviderExtension/SearchSupport.swift`. The
extension adopts `NSFileProviderSearching` (macOS 26+), and
`CloudSearchEnumerator` runs #65's `RcloneClient.search` and returns
`FileProviderItem`s as results. The app sets `supportsStringSearchRequest`
on new domains. It updates existing domains in place with
`NSFileProviderManager.add` and the same identifier.

Live, with the build installed:

- The in-place update worked. All three domains logged "Turned on system
  search", and `fileproviderctl dump` shows `features: repl,syncTrash,search`.
  Downloaded files stayed downloaded (MCS: 2 materialized before and after).
- `mdfind` never calls the extension; it only reads the local index.
- A Finder search scoped to "Nimbus - Google Drive" for a file in a folder
  nobody has opened returned 0 items. The extension logged no search call.
- The Spotlight panel (⌘Space) couldn't be driven by automation here: it
  runs in the Siri process. That check is manual: type the query and look
  for a `search` line in the extension log
  (`log show --predicate 'subsystem == "app.casavargas.nimbus.FileProvider" AND category == "search"'`).

**Spotlight panel, manual check (Jon):** the file wasn't found, and
Spotlight said it was still indexing. The extension logged no search call.
`mds_stores` was at about 95% CPU, so a system-wide reindex was running
through this whole session. That confounds every Spotlight result above:
the missing local items, the new folders that stayed unindexed, and maybe
the provider search not running. **Re-run all the checks once
`mds_stores` is idle** before deciding between the working set and
`NSFileProviderSearching`.

`fileproviderctl dump` also shows fileproviderd running its own Spotlight
indexer for each Nimbus domain (MCS: `total-indexable-count: 119`,
`pending: 0`). So local items are donated without any working-set listing.
The indexer's scheduler sat asleep through the test, which may explain
why newly listed items took longer than 7 minutes to appear.

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
