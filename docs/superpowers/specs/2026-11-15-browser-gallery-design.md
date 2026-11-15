# Browser Gallery Mode — Design

**Date:** 2026-11-15
**Status:** Draft, waiting on Jon's approval. Nothing is built.
**Issue:** none yet (README "Not done yet": "Media gallery and other advanced browser modes").
**Builds on:** `Views/Browser/` (`FileGrid`, `BrowserToolbar`, `Selection<String>`),
`Shared/Thumbnails.swift` (`ThumbnailPolicy`, `ThumbnailRenderer`, `ThumbnailCache`),
`Interaction/QuickLookHost.swift` (`downloadToTemp`).

## Why

A folder of photos or scans in the Nimbus browser is a wall of identical generic icons: list
and grid both draw `FileIcon`, never the picture. Finder shows thumbnails for the same files
(the File Provider extension draws them), so the app's own browser is the worse place to look
through media. Competitors with a browser (ForkLift, Commander One) have a preview or gallery
mode.

## Today

- `ViewMode` has `.list` and `.grid`. The toolbar has a two-segment picker; the View menu has
  "as List" (⌘1) and "as Grid" (⌘2).
- The app draws no thumbnails. The extension does, for Finder: photos and PDFs up to 20 MB are
  downloaded to a temp file, drawn, cached (200 MB, least recently used out first), and the
  temp file is deleted. That code is in `Shared/` and already builds into the app.

## Decision

1. **A third view mode, Gallery** (⌘3, third toolbar segment), shaped like Finder's: one large
   preview of the selected item over a filmstrip of the folder.
2. **Thumbnails follow the Finder rules exactly:** photos and PDFs up to
   `ThumbnailPolicy.maxSourceBytes`; everything else (video, audio, folders, large files)
   shows its file icon. One rule for both places.
3. **Only what's on screen is fetched.** Filmstrip cells load when they appear, at most three
   downloads at once, and results go to a cache in the app's Caches folder.

## Screen

```
┌──────────────────────────────────────────────────────────┐
│ Google Drive › Photos › 2026                             │  breadcrumb (unchanged)
├──────────────────────────────────────────────────────────┤
│                                                          │
│                 ┌──────────────────────┐                 │
│                 │                      │                 │
│                 │    large preview     │                 │  fits the pane, keeps
│                 │   of the selection   │                 │  its aspect ratio
│                 │                      │                 │
│                 └──────────────────────┘                 │
│            IMG_2041.heic · 3.1 MB · 12 Nov 2026          │
├──────────────────────────────────────────────────────────┤
│ [▢] [▢] [▣] [▢] [▢] [▢] [▢] [▢] [▢] [▢] [▢] [▢] [▢]  →  │  filmstrip, scrolls sideways
└──────────────────────────────────────────────────────────┘
```

- **Preview:** the selected item drawn at up to 1600 px on its long side. While it loads, the
  filmstrip thumbnail (if cached) stands in, then the file icon. Files with no thumbnail show
  a large file icon. Nothing selected: the first item is selected on entering the mode.
- **Caption:** name, size, modified date, in the existing caption typography.
- **Filmstrip:** 72 pt cells in the folder's current sort order, selected cell ringed with the
  selection color and kept scrolled into view.
- **Keys and clicks:** ← and → move the selection; double-click or Return opens (folders
  navigate, files open as in grid); Space is Quick Look; the context menu and drag payload are
  the ones `FileGrid` uses. Multi-selection in the filmstrip is out for v1.
- **Empty, loading and error states** are the browser's existing ones; Gallery only replaces
  the content area.

## How

- `ViewMode` gains `.gallery`; `BrowserView`'s switch, `BrowserToolbar`'s picker and
  `AppCommands` each get the third case.
- New `Views/Browser/FileGallery.swift`: the preview, caption and filmstrip.
- New `Services/BrowserThumbnailLoader.swift`, an actor: given remote, full path, size,
  modified time and a pixel size, it returns a `CGImage` or nil. It checks `ThumbnailPolicy`,
  then `ThumbnailCache` (key built from `remote:path`, with size and modified time standing
  in as the content version), otherwise downloads with `downloadToTemp`, draws with
  `ThumbnailRenderer`, stores, and deletes the temp file. It caps concurrent downloads at
  three and cancels work for cells that scroll away.
- An in-memory `NSCache` in front of the disk cache so scrolling back doesn't decode again.

## Approaches considered

| | What | Trade-off |
|---|---|---|
| **A. Gallery mode (chosen)** | Preview over filmstrip, reusing the Finder thumbnail code | Matches the README line and Finder; one new view and one loader |
| B. Thumbnails in the existing grid plus a size slider | No new mode; grid tiles show pictures | Cheaper, but there is no large preview, and every grid visit starts downloading |
| C. Embed `QLPreviewView` as the preview | Full Quick Look fidelity, video included | Downloads the whole file for every selection with no size cap; arrowing through a folder of videos would pull gigabytes |

B is a sensible follow-up once the loader exists. C stays available through Space.

## Not in this change

- Thumbnails in list or grid mode.
- Video and audio previews beyond the file icon.
- Remembering the view mode per folder or across launches (it isn't remembered today).
- Column view, tabs, dual pane. These are what "other advanced browser modes" would mean; the
  README line gets reworded to name them when Gallery ships.

## Cost to the user

rclone has no thumbnail call, so a thumbnail costs one download of the file (up to 20 MB
each). A folder of 500 photos is not fetched up front: only the cells on screen, three at a
time, and each is fetched once until the file changes or the 200 MB cache evicts it.

## Tests

- `BrowserThumbnailLoaderTests`: policy skips (too large, wrong type, unknown size), cache hit
  skips the download, a changed size or date misses the cache, the temp file is removed,
  failure returns nil. Uses a fake `RcloneClientProtocol`.
- `FileGallerySelectionTests`: ← and → stepping, clamping at both ends, first-item selection
  on entry.
- `FileGallerySnapshotTests`: a folder with a photo, a PDF, a folder and a large file, with a
  stubbed loader, via `SnapshotHelpers`.
- Live check in the running app against a real cloud folder before the PR is marked ready.
