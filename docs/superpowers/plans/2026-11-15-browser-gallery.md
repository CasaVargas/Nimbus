# Browser Gallery Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third browser view mode, Gallery: a large preview of the selected item over a filmstrip, with thumbnails for photos and PDFs.

**Architecture:** A `BrowserThumbnailLoader` actor in the app reuses `Shared/Thumbnails.swift` (policy, renderer, disk cache, `AsyncLimiter`) and downloads through `RcloneClientProtocol.downloadToTemp`. `FileGallery` is a SwiftUI view driven by the existing `Selection<String>`; its stepping rules live in a pure `GallerySelection` enum.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, ImageIO.

**Spec:** `docs/superpowers/specs/2026-11-15-browser-gallery-design.md`

## Global Constraints

- Thumbnails only where `ThumbnailPolicy.kind(for:size:)` is non-nil (photos and PDFs, at most 20 MB).
- At most 3 downloads at once; only cells on screen are requested.
- Preview is drawn at 1600 px, filmstrip cells are 72 pt (144 px).
- No `.system(size:)` outside `DesignSystem/`; no new packages.
- After `xcodegen generate`, run `git checkout -- Nimbus/FileProviderExtension/Info.plist`.

## Review Focus

- A file whose download fails or whose bytes don't decode: the cell shows the file icon, nothing throws.
- A folder with no thumbnailable file: Gallery works on icons alone and starts no download.
- The selected item is deleted or the folder changes: selection moves to the first item, never to a stale ID.
- A cell scrolls away before its turn: no download starts for it.
- The same file edited in the cloud (new size or date): the old picture is not shown.

---

### Task 1: Thumbnail loader

**Files:**
- Create: `Nimbus/Nimbus/Services/BrowserThumbnailLoader.swift`
- Test: `Nimbus/NimbusTests/BrowserThumbnailLoaderTests.swift`

**Interfaces (produces):**

```swift
struct ThumbnailRequest: Hashable, Sendable {
    let remote: String; let path: String   // full path from the remote root
    let name: String; let size: Int64; let modTime: Date?; let maxPixel: Int
    init(file: FileItem, remote: String, maxPixel: Int)
    var kind: ThumbnailPolicy.Kind?        // from the name's extension and size
    var cacheKey: String                   // ThumbnailCache.key over "remote:path", "size|modTime", maxPixel
}
protocol GalleryThumbnailProviding: Sendable {
    nonisolated func cachedImage(for request: ThumbnailRequest) -> CGImage?   // memory only, synchronous
    func image(for request: ThumbnailRequest) async -> CGImage?
}
actor BrowserThumbnailLoader: GalleryThumbnailProviding {
    init(client: any RcloneClientProtocol, cache: ThumbnailCache?, limiter: AsyncLimiter = AsyncLimiter(limit: 3))
    static func defaultCache() -> ThumbnailCache?   // <Caches>/BrowserThumbnails
}
```

- [ ] Tests (fake client counting downloads, real PNG written to temp, scratch cache dir): `skipsFilesThePolicyRejects` (30 MB photo, `.txt`, size -1: nil and 0 downloads), `drawsAndCachesAPhoto` (non-nil, long side ≤ maxPixel, second call 0 new downloads, also from a fresh loader on the same disk cache), `changedSizeOrDateMissesTheCache`, `removesTheTempFile`, `failedDownloadReturnsNil`, `undecodableBytesReturnNil`, `cancelledBeforeItsTurnDoesNotDownload`.
- [ ] Run them, see them fail to compile.
- [ ] Implement. `image(for:)`: policy → memory → disk → `limiter.acquire()` → cancellation check → download → render off the actor → store → delete the temp directory.
- [ ] Run them, see them pass. Commit.

### Task 2: Selection rules

**Files:**
- Create: `Nimbus/Nimbus/Views/Browser/GallerySelection.swift`
- Test: `Nimbus/NimbusTests/GallerySelectionTests.swift`

**Interfaces (produces):**

```swift
enum GallerySelection {
    /// The one item Gallery shows: the selected ID that comes first in `ids`, else the first ID.
    static func current(selected: Set<String>, in ids: [String]) -> String?
    /// The neighbour `delta` away, clamped to both ends; the first ID when nothing valid is selected.
    static func step(from current: String?, by delta: Int, in ids: [String]) -> String?
}
```

- [ ] Tests: empty list → nil; nothing selected → first; stale ID → first; step ±1; clamps at both ends; multi-selection → earliest in order.
- [ ] Implement, pass, commit.

### Task 3: Gallery view and wiring

**Files:**
- Create: `Nimbus/Nimbus/Views/Browser/FileGallery.swift`
- Modify: `ViewModels/BrowserViewModel.swift` (`ViewMode.gallery`), `Views/Browser/BrowserView.swift` (switch case, loader in `@State`), `Views/Browser/BrowserToolbar.swift` (third segment, `squares.below.rectangle`, help text), `Views/AppCommands.swift` ("as Gallery", ⌘3)
- Test: `Nimbus/NimbusTests/FileGallerySnapshotTests.swift` + fixture

**Interfaces (consumes):** Task 1 and 2 types.

```swift
struct FileGallery: View {
    init(files: [FileItem], remote: String, selection: Selection<String>,
         thumbnails: (any GalleryThumbnailProviding)?,
         onOpen: @escaping (FileItem) -> Void,
         onContextAction: @escaping (FileItem, FileAction) -> Void,
         onQuickLook: @escaping ([FileItem]) -> Void)
    enum Layout { static let cellSize: CGFloat = 72; static let previewMaxPixel = 1600 }
}
```

- [ ] Snapshot test: photo, PDF, folder and a 30 MB file with a stub provider that answers `cachedImage` synchronously; photo selected.
- [ ] Implement: preview + caption + filmstrip; ←/→/Return/Space via `onKeyPress`; context menu and drag payload as `FileGrid`; selection repaired through `GallerySelection.current` on appear and when `files` changes.
- [ ] `xcodegen generate`, restore the extension Info.plist, build, full test run.
- [ ] Live check in the running app on a real cloud folder; screenshot.
- [ ] README: move Gallery to the done list, reword the remaining line to "Column view, tabs and dual pane in the browser". Commit, push, PR.
