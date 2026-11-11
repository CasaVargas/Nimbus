# Search Across Clouds — Design

**Date:** 2026-11-11
**Status:** Building (issue #65)
**Research:** `docs/superpowers/reports/2026-11-11-feature-parity.md`
**Area:** RcloneKit (`RemoteSearch.swift`), `SearchViewModel`, `Views/Search/`, `ContentView`

## Why

Nimbus has no search field anywhere. Cyberduck, ForkLift, Commander One and Rclone UI search
one remote at a time. None of them searches every cloud at once. That gap is where Nimbus can
stand out.

## What rclone gives us (checked on rclone 1.76.0, 2026-11-11)

- `operations/list` with `opt.recurse = true` lists a whole tree.
- `_filter.IncludeRule = ["*{{(?i)<regex>}}*"]` keeps only the files whose **name** matches.
  A rule with no leading `/` matches the last path segment at any depth. **Folders are always
  returned**, whatever the filter says, so the client filters folder names itself.
- `_config.MaxDepth = N` caps recursion. (`_filter.MaxDepth` is silently ignored.)
- `_async = true` returns `{jobid}`. `job/status` carries the listing in `output` once
  `finished`, and `job/stop` stops the listing on the daemon. Without this, cancelling the
  HTTP request leaves rclone walking the tree.
- Filtering happens inside rclone after it lists each folder, so the backend still lists every
  folder. What the filter saves is the JSON sent to the app, not the API calls to the cloud.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Scope | **Every cloud**, in parallel. An alias whose target is another configured cloud is skipped, so the same files are not listed twice. | Searching every cloud at once is the gap this feature fills. |
| Match | Case-insensitive substring on the **name**, for files and folders. At least 2 characters. | This is what Finder's name search does. Two characters keeps a one-letter query from walking every cloud. |
| Depth | `MaxDepth` **10** below the cloud root. | Deep enough for real folder trees. Cost depends on how many folders a cloud has more than on depth, so the time limit does the real bounding. |
| Time limit | **60 s per cloud**. When it runs out, Nimbus stops that cloud's job and shows "Took too long — narrow the search or browse instead". | One slow cloud must not hold up the others or run forever. |
| Result cap | Up to **200 per cloud** are shown, sorted by name. If there are more, the header says "Showing 200 of N". | A long list is useless. The query is the fix. |
| Cancel | Typing restarts the search after a **400 ms** pause. A new query, clearing the field or leaving search cancels the Swift tasks, and each one sends `job/stop` for its rclone job. | rclone keeps listing unless it is told to stop. |
| Cache | **None.** Every search is live. | Results are always current and there is no stale state to manage. A per-session index or backend-native search (Drive `search`, S3 prefix) can come later if live search proves slow. |
| Failure | A cloud that fails shows its error in its own section. The other clouds still show their results. | One signed-out cloud should not hide results from the rest. |

## UI

- **Field:** a standard `.searchable` field in the window toolbar, labelled "Search all clouds".
  ⌘F focuses it (Edit ▸ Find).
- **Results:** while the trimmed query has at least 2 characters, the detail pane shows
  `SearchResultsView` in place of the current screen. Clearing the field brings the previous
  screen back. The sidebar selection is not changed.
- One section per cloud, headed by the provider logo and name, and one of: a spinner while it
  searches, "N results", "No matches", "Showing 200 of N", or the error.
- **Row:** file icon, name, parent folder (`Work/2026`, or "Top level"), size for files, date
  modified.
- **Actions:**
  - Double-click, or **Show in Nimbus**, opens that cloud's Files tab at the parent folder and
    clears the search.
  - **Show in Finder**, only for clouds shown in Finder: gets the item's URL from the File
    Provider (`FileProviderBridge.urlForItem`) and selects it in Finder.
  - **Copy Path** copies `remote:path`.
- Before anything has been typed, or below 2 characters, the pane shows a short hint:
  "Type at least two letters to search every cloud".

## Out of scope

- Spotlight (separate issue).
- Content search, filters by kind, size or date.
- Selecting the file once the browser has opened its folder. The browser has no
  "select this item" input yet, so it is a follow-up.
- Backend-native search APIs.

## Tests

- RcloneKit: the params sent (`recurse`, `IncludeRule`, `MaxDepth`, `_async`); regex
  metacharacters in the query are escaped; folders with names that don't match are dropped;
  cancelling during polling sends `job/stop` and throws `CancellationError`; a failed job
  throws its error.
- `SearchViewModel` with a scripted client: results from 3 clouds are kept per cloud; one
  failing cloud records its error and the others still finish; a new query cancels the old one,
  so stale results never appear; aliases of configured clouds are skipped; the cap and the
  "of N" total are applied.
