# File Provider Complete Implementation — Design Spec

**Goal:** Make the File Provider extension production-ready with real change tracking, lifecycle UI, error recovery, and thumbnail support.

**Parent initiative:** Nimbus premium v1 launch — File Provider sub-projects 3-6

---

## Sub-project 3: Change Tracking

### Scope
Replace the stubbed `enumerateChanges()` with timer-based polling that detects changes on the remote and pushes them to Finder.

### Behavior
- Every 30 seconds, the enumerator re-lists the current directory from rclone
- Compares the new listing to a cached snapshot (keyed by item identifier)
- Emits new/updated items via `observer.didUpdate()`
- Emits deleted item identifiers via `observer.didDeleteItems(withIdentifiers:)`
- Sync anchor is a timestamp encoded as Data — Finder passes it back on the next `enumerateChanges` call
- The cached snapshot is stored in-memory on the enumerator instance (not persisted — Finder re-enumerates on extension restart)

### Files changed
- **Modify: `src-tauri/FileProviderExtension/FileProviderEnumerator.swift`** — Implement real `enumerateChanges()` with snapshot diffing. Add a `cachedItems` dictionary. Update `currentSyncAnchor` to use the last enumeration timestamp.
- **Modify: `src-tauri/FileProviderExtension/RcloneClient.swift`** — Add `listDirectoryRaw(remotePath:)` returning `[[String: Any]]` for snapshot comparison (the existing `listDirectory` returns `[NSFileProviderItem]` which doesn't preserve raw data for diffing).

---

## Sub-project 4: Mount Lifecycle UI

### Scope
Show domain registration status on fileprovider mount items. Allow re-registering failed domains.

### Behavior
- The mount item for fileprovider shows one of:
  - Green dot + "Registered" — domain exists in `fpListDomains()` results
  - Red dot + "Not registered" — domain missing from `fpListDomains()` results
- A "Re-register" button appears when the domain is not registered
- Clicking "Re-register" calls `fpAddDomain` and shows toast feedback
- The `useActiveMounts` hook already polls `fpListDomains()` every 10 seconds — we use this data to determine status

### Files changed
- **Modify: `src/features/mount/components/mount-item.tsx`** — Check if the fileprovider domain is in the active mounts list. Show status text and re-register button when not registered.

---

## Sub-project 5: Error Recovery

### Scope
Handle daemon disconnects, port changes, and stale domains gracefully.

### Extension-side (Swift)
- `RcloneClient` retries failed requests up to 3 times with exponential backoff (1s, 2s, 4s)
- On each retry, re-read `SharedState` to pick up port changes (the main app may have restarted rclone on a different port)
- If all retries fail, propagate the error to Finder (which shows a "connection failed" banner)

### App-side (Rust)
- On app launch, compare registered domains (from `fp_list_domains`) against current mount configs
- Remove any domains that don't have a matching mount config (stale domains from unclean shutdowns)
- Expose this as `fp_cleanup_stale_domains` Tauri command

### Frontend
- Call `fp_cleanup_stale_domains` once on app startup after the daemon connects
- The existing `useFileProviderSync` hook is the right place for this

### Files changed
- **Modify: `src-tauri/FileProviderExtension/RcloneClient.swift`** — Add retry wrapper around `rcCall`. Re-read port from SharedState on each retry.
- **Modify: `src-tauri/src/commands/file_provider.rs`** — Add `fp_cleanup_stale_domains` command that reads mount configs and removes unmatched domains.
- **Modify: `src-tauri/src/lib.rs`** — Register the new command.
- **Modify: `src/lib/tauri/file-provider.ts`** — Add `fpCleanupStaleDomains()` wrapper.
- **Modify: `src/hooks/use-file-provider-sync.ts`** — Call cleanup on first sync.

---

## Sub-project 6: Thumbnails & Metadata

### Scope
Implement `NSFileProviderThumbnailing` so Finder shows image/video previews instead of generic icons.

### Behavior
- The extension conforms to `NSFileProviderThumbnailing`
- `fetchThumbnails(for:requestedSize:perThumbnailCompletionHandler:completionHandler:)` is implemented
- For image files (UTType conforms to `.image`): download the file via rclone, create a CGImage thumbnail using ImageIO, return it
- For video files (UTType conforms to `.movie`): skip (too expensive to download for a thumbnail). Return nil.
- For all other file types: return nil (Finder uses UTType-based icons)
- Thumbnail downloads go to a temp directory and are cleaned up after thumbnail generation
- Maximum thumbnail file size: 10MB. Skip files larger than this to avoid slow downloads.

### Files changed
- **Modify: `src-tauri/FileProviderExtension/FileProviderExtension.swift`** — Conform to `NSFileProviderThumbnailing`, implement `fetchThumbnails`.
- **Modify: `src-tauri/FileProviderExtension/FileProviderItem.swift`** — Report `.allowsThumbnails` in capabilities for image files.
- **Modify: `src-tauri/FileProviderExtension/RcloneClient.swift`** — Add `downloadFileToTemp(identifier:)` variant that returns just the URL (no item fetch needed for thumbnails).
