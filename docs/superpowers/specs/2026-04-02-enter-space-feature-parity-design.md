# Enter Space Feature Parity Design

**Date:** 2026-04-02
**Status:** Draft
**Approach:** Tier-sequential, parallel platforms (Tauri + SwiftUI)

## Overview

Nimbus adopts 12 features inspired by Enter Space, organized into four tiers. Both the Tauri app (`src/`, `src-tauri/`) and SwiftUI app (`Nimbus/`, `RcloneKit/`) receive each feature, except OS-integration features (Tier 4) which land in SwiftUI first with Tauri support added later via a Swift helper binary.

## Decisions Summary

| Decision | Choice |
|----------|--------|
| Target apps | Both Tauri and SwiftUI in parallel |
| Tier ordering | 1 (foundations) → 2 (power) → 3 (rich experience) → 4 (OS integration) |
| Scheduled sync execution | App-only first, designed for background (LaunchAgent) later |
| Media gallery scope | Full experience: slideshow, 360 video, background audio, embedded artwork |
| Code editor | Delegate to system default app — no built-in editor |
| Encryption UX | Guided wizard for common cases + advanced mode for raw crypt config |
| Spotlight & Shortcuts | SwiftUI only initially, Tauri later via Swift helper |

---

## Tier 1: Foundations

### 1.1 rclone.conf Import

**Goal:** Let users import an existing rclone configuration file to bootstrap remotes.

**Flow:**
1. "Import Config" button on the Remotes page
2. File picker filtered to `.conf` files (accepts any file for non-standard names)
3. Parse the `.conf` file client-side (INI format: `[remoteName]` sections with `key = value` pairs) — do NOT modify rclone's active config file
4. Present preview list: "Found N remotes — select which to import"
5. User checks/unchecks remotes, hits Import
6. Each selected remote created via `config/create` RC API calls (one call per remote, passing `name`, `type`, and `parameters`)
7. Conflicts (remote name already exists) shown inline with rename option

**Platform details:**
- Tauri: file dialog via `tauri::dialog`
- SwiftUI: `.fileImporter()` modifier

### 1.2 Folder Bookmarks

**Goal:** Quick-access shortcuts to frequently used paths within any remote.

**Data model:**
```typescript
interface Bookmark {
  id: string
  remoteName: string
  path: string
  label: string
  order: number
}
```

**Behavior:**
- Right-click a folder in the browser → "Add to Bookmarks"
- Displayed in the sidebar under a "Bookmarks" section, below existing navigation items
- Click a bookmark → navigates browser to that remote + path
- Drag to reorder, right-click to rename/remove
- Synced to File Provider extension via app group UserDefaults (bookmarked folders optionally appear as Finder favorites)

**Storage:**
- Tauri: Zustand store with persistence
- SwiftUI: UserDefaults or SwiftData

### 1.3 Download/Evict Management

**Goal:** User control over which files are materialized locally vs. cloud-only stubs in the File Provider.

**Behavior:**
- Leverages `NSFileProviderItemCapabilities` for `.evictable` and the system's download/evict API
- Browser UI: "cloud status" column/indicator showing materialized vs. evicted state
- Context menu actions: "Download Now" (materialize) / "Remove Local Copy" (evict)
- Bulk operations: select multiple files → "Free up space" to evict all
- Settings: storage usage summary — "X GB cached locally across Y remotes"

**Platform details:**
- File Provider extension already handles materialization — this adds explicit user control
- Both apps add the browser column and context menu items

---

## Tier 2: Power Features

### 2.1 Client-Side Encryption (rclone crypt)

**Goal:** Encrypt files before upload using rclone's crypt remote type, with both guided and advanced configuration.

#### Wizard Mode (Guided)

1. From any existing remote, user clicks "Encrypt this Remote" (context menu or detail view)
2. **Step 1:** Choose scope — full remote or a specific subfolder path
3. **Step 2:** Set password (with strength indicator) and optional salt password
4. **Step 3:** Choose filename encryption: `standard` (encrypted), `obfuscate`, or `off`
5. **Step 4:** Preview — crypt remote name (e.g., `gdrive-encrypted`), underlying path, settings
6. **Step 5:** Create via `config/create` with `type=crypt`, `remote=<underlying>`, `password=<obscured>`, `password2=<obscured>`

The new crypt remote appears in the remotes list with a lock icon badge.

#### Advanced Mode

"Crypt" appears as a remote type in the standard Add Remote flow. User fills in raw config fields. Same `config/create` call.

#### Password Handling

- Passwords obscured via `config/password` RC endpoint before storage
- Nimbus never stores plaintext passwords
- SwiftUI: optionally store in Keychain via `SecItemAdd`

### 2.2 Scheduled Syncs

**Goal:** Automated sync/copy jobs on a configurable schedule with filtering, designed for future background execution.

#### Schedule Configuration

- New "Scheduled Syncs" section accessible from sidebar or as a tab within Copy/Sync
- Create a job: source remote+path, destination remote+path, operation (sync/copy), schedule (hourly/daily/weekly/custom cron)
- Filter options: include/exclude glob patterns, min/max file size, max age
- Dry-run toggle to preview before enabling
- Each job has: name, enabled/disabled toggle, last run timestamp, last run status

#### Job Data Model

```typescript
interface ScheduledSyncJob {
  id: string
  name: string
  enabled: boolean
  sourceRemote: string
  sourcePath: string
  destRemote: string
  destPath: string
  operation: "sync" | "copy"
  schedule: {
    type: "interval" | "cron"
    interval?: "hourly" | "daily" | "weekly"
    cron?: string
  }
  filters: {
    include?: string[]
    exclude?: string[]
    minSize?: string
    maxSize?: string
    maxAge?: string
  }
  dryRun: boolean
  lastRun?: string  // ISO timestamp
  lastRunStatus?: "success" | "error" | "cancelled"
}
```

#### Execution (Phase 1 — App-Only)

- In-app scheduler checks pending jobs while the app is running
- Fires `sync/sync` or `sync/copy` RC API call with filter parameters
- Progress shown in Transfers view, tagged with schedule name
- Missed schedules run immediately on next app launch with notification

#### Designed for Phase 2 (Background)

- Job definitions stored in shared location (JSON in app group container)
- Future LaunchAgent can read the same job definitions and execute them
- Scheduler interface abstracted so swapping in a LaunchAgent executor requires no UI changes

#### Filter Mapping

Filters map directly to rclone RC API flags: `--include`, `--exclude`, `--min-size`, `--max-size`, `--max-age`.

### 2.3 Public Link Sharing

**Goal:** Generate shareable public links for files/folders on providers that support it.

**Flow:**
1. Context menu on file/folder in browser → "Copy Share Link"
2. Call `operations/publiclink` RC API with `fs=<remote>:` and `remote=<path>`
3. Success: URL copied to clipboard, toast notification
4. Unsupported provider: message "This provider doesn't support public links"
5. Optional: set expiry via provider-specific flags

**SwiftUI bonus:** NSSharingServicePicker for richer sharing options.

---

## Tier 3: Rich Experience

### 3.1 Media Gallery

**Goal:** Browse and play photos, videos, and audio from any remote with a rich, immersive viewer.

#### Gallery View Mode

- New view mode toggle in browser toolbar alongside list/grid: gallery icon
- Filters current directory to media files by MIME type/extension
- Thumbnail grid — generated via rclone or by downloading low-res versions
- Thumbnail cache: app's cache directory, encrypted at rest

#### Photo Viewer

- Click thumbnail → full-screen overlay viewer
- Swipe/arrow keys to navigate between images in folder
- Zoom (pinch/scroll), pan, rotate
- EXIF metadata panel: date, camera, dimensions, GPS
- Slideshow mode: auto-advance (3s/5s/10s configurable), shuffle option

#### Video Player

- Streams via rclone's HTTP serving (RC server's file serving endpoint or `rclone serve http`)
- Tauri: `<video>` element with range requests against rclone HTTP endpoint
- SwiftUI: `AVPlayer` with URL to rclone's local HTTP server
- 360-degree video: detect via metadata, render with SceneKit (SwiftUI) or WebGL spherical viewer (Tauri)

#### Audio

- Embedded artwork from ID3 tags
- Mini-player bar at bottom of window (like Music.app): track name, play/pause, progress scrubber
- Background audio: SwiftUI uses `AVAudioSession` with `.playback` category; Tauri `<audio>` plays when window unfocused
- Continues playing while browsing other folders

### 3.2 Open in Default Editor

**Goal:** Quick action to open any file in the system's default application, with change detection.

**Flow:**
1. Context menu → "Open With..." / "Open in Default App"
2. Download/materialize file to temp directory if not cached
3. Open: Tauri uses `tauri::shell::open` / `opener::open`; SwiftUI uses `NSWorkspace.shared.open(url)`
4. Watch temp file for modifications (FSEvents)
5. If modified: prompt "File was modified. Upload changes?" → upload via `operations/copyfile`

### 3.3 File Versioning / Time Portal

**Goal:** Browse and restore previous versions of files.

#### Provider-Native Versioning (S3, GCS, B2, etc.)

- Context menu → "Version History"
- Provider-specific RC API calls with `--b2-versions` / `--s3-versions` flags
- Timeline list: version ID, timestamp, size
- "Preview" opens version in viewer; "Restore" copies version back to current path

#### Sync-Based Versioning

- Scheduled syncs optionally configure `--backup-dir` for previous versions in dated subfolders (e.g., `remote:backups/2026-04-02/`)
- Time Portal UI: calendar/timeline picker → browse backup directory for that date
- Restore: copy old version back to original path

---

## Tier 4: OS Integration (SwiftUI First)

### 4.1 Spotlight Indexing

**Goal:** Cloud files appear in macOS Spotlight search results.

**Implementation:**
- Core Spotlight (`CSSearchableIndex`) indexes file metadata (not contents)
- Indexed fields: file name, path, remote name, MIME type, modification date, size
- Incremental indexing: triggered when user browses a folder or scheduled syncs run
- Unique identifier per item: `nimbus://<remote>/<path>`
- Spotlight result activation: opens Nimbus, navigates to file via `NSUserActivity`
- Periodic re-index of bookmarked folders and recently browsed paths
- Settings toggle: "Enable Spotlight Indexing" (off by default for large remotes)

**SwiftUI only initially.** Tauri later via Swift helper binary managing `CSSearchableIndex`.

### 4.2 Apple Shortcuts Integration

**Goal:** Expose Nimbus actions as App Intents for Shortcuts automation.

**Intents:**

| Intent | Description |
|--------|-------------|
| `ListRemotes` | Returns list of configured remotes |
| `BrowseFolder` | Returns file listing for remote + path |
| `CopyFile` | Copy file between remotes or to/from local |
| `SyncFolder` | Trigger sync between two paths |
| `MountRemote` | Mount a remote |
| `UnmountRemote` | Unmount a remote |
| `RunScheduledSync` | Trigger a named scheduled sync immediately |
| `GetStorageUsage` | Return usage stats via `operations/about` |

**Implementation:**
- Each intent is an `AppIntent` struct with `@Parameter` inputs and typed returns
- Grouped under `AppShortcutsProvider` with suggested shortcuts (e.g., "Back up my photos", "Mount work drive")
- Intents call existing service layer (`RcloneDaemon`, `MountManager`, etc.)
- `DynamicOptionsProvider` for remote/path selection in Shortcuts editor

**SwiftUI only initially.** Tauri later via Swift helper.

### 4.3 Photos Library Backup

**Goal:** Back up Apple Photos Library to any cloud remote.

**Flow:**
1. Dedicated "Photos Backup" option within Scheduled Syncs
2. Uses PhotoKit (`PHAsset` enumeration) to export to temp staging directory
3. Preserves album structure as folders
4. Configurable export format: original (HEIC/MOV) or compatible (JPEG/MP4)
5. Folder structure: `Photos/2026/04/IMG_1234.heic`
6. Staging directory synced to destination via `sync/sync` RC call
7. Incremental: local manifest tracks asset ID → last modified date
8. Staging files removed after successful upload

**Progress:** "Exporting 234/1,200 photos... Uploading 89/234..."

**Privacy:** Requires Photos access permission. First run triggers macOS permission dialog. Settings shows permission status.

**SwiftUI only initially.** PhotoKit is a native framework. Tauri later via Swift helper.

---

## Cross-Cutting Concerns

### Shared State

Features that affect the File Provider extension (bookmarks, download/evict, Spotlight) sync state via the existing app group UserDefaults mechanism (`group.app.casavargas.nimbus`).

### Error Handling

All RC API calls use existing error handling patterns:
- Tauri: error toast via frontend notification system
- SwiftUI: `.alert` modifiers on views, errors surfaced through view models

### Testing Strategy

- Unit tests for data models and transformations (Vitest for Tauri frontend, XCTest for SwiftUI/RcloneKit)
- Integration tests for RC API call sequences (mock rclone HTTP responses)
- Manual testing for File Provider interactions (not easily automated)

### Migration Path

If the Tauri app is sunset before all tiers ship:
- Tier 1-3 features are thin UI over rclone RC API — migration cost is low
- Tier 4 is SwiftUI-native — no migration needed
- Shared data (bookmarks, scheduled sync jobs) stored in app group container, accessible from both apps
