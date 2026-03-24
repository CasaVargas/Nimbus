# StreamCloned — Design Spec

**Date:** 2026-03-23
**Status:** Draft
**Codename:** StreamCloned (working title)
**License:** Open source (TBD — likely MIT or Apache-2.0)

## Overview

StreamCloned is a cross-platform desktop GUI for rclone & S3. It targets macOS, Windows, and Linux. The goal is to obliterate Rclone UI by shipping a leaner, better-designed, more intuitive app using the same foundational stack (Tauri + React/TypeScript) but with superior UX, cleaner architecture, and zero bloat.

### Strategy

Ship lean (v1: core file operations), make it gorgeous, then layer on power features incrementally.

- **v1:** Browse, Copy, Sync, Mount, Transfer Queue — the essentials done flawlessly
- **v2:** Dual-panel commander, cron scheduling, serve, templates
- **v3+:** Multi-host management, bisync, mobile companion

### Competitive Edge

- Design-first: Arc-browser-level polish vs Rclone UI's developer-tool aesthetic
- Simplicity: Focused feature set vs Rclone UI's 20-window sprawl
- Performance: Same Tauri foundation but without the bloat
- Open source: Community-driven, no paywall upsells

---

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Runtime | Tauri v2 | Cross-platform native shell, Rust backend, small binary |
| Frontend | React 19 + TypeScript 5.x | Industry standard, massive ecosystem |
| Bundler | Vite 6 | Fast builds, HMR, modern defaults |
| Styling | Tailwind CSS v4 | Utility-first, no CSS bloat |
| UI Components | shadcn/ui | Copy-paste ownership, no dependency lock-in |
| Client State | Zustand | Minimal, fast, TypeScript-native |
| Server State | TanStack Query v5 | Caching, deduplication, background refetch for rclone API |
| Routing | React Router v7 | Standard, well-supported |
| Icons | Lucide React | Clean, consistent, tree-shakeable |
| Linting/Formatting | Biome | Fast, single tool for lint + format |

### Why Not HeroUI (like Rclone UI)?

shadcn/ui gives full ownership of every component file. No version lock-in, no fighting upstream design opinions, no waiting for library updates. We control the design system completely.

---

## Architecture

### Principle: Thin Rust, Fat TypeScript

Rust handles **only** system-level operations that cannot be done from the web layer:

- Rclone binary bundling and process lifecycle (spawn/stop daemon)
- System tray with native menus
- Mount/unmount via OS-level syscalls
- Auto-updater (Tauri built-in)

**Everything else** lives in TypeScript: rclone API communication, state management, file browser logic, transfer orchestration, UI rendering.

### Communication Paths

```
┌─────────────────────────────────────────────┐
│                  Frontend                     │
│  React 19 + TypeScript + Zustand + TanStack  │
│                                               │
│  ┌─────────────┐      ┌──────────────────┐   │
│  │ Zustand      │      │ TanStack Query   │   │
│  │ (UI state)   │      │ (rclone API)     │   │
│  └─────────────┘      └───────┬──────────┘   │
│                                │               │
└────────────────────────────────┼───────────────┘
          │ Tauri IPC            │ HTTP
          ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│   Rust Backend   │    │  rclone daemon   │
│   (thin layer)   │    │  (localhost:5572)│
│                  │    │                  │
│  - Process mgmt  │───▶│  - 40+ providers │
│  - System tray   │    │  - File ops      │
│  - Mount syscalls│    │  - OAuth flows   │
│  - Auto-updater  │    │  - VFS cache     │
└─────────────────┘    └─────────────────┘
```

- **Frontend → rclone daemon:** HTTP requests to `localhost:5572` via TanStack Query. This is the primary communication channel for all file operations, remote config, and transfers.
- **Frontend → Rust:** Tauri IPC commands, used sparingly for system tray, process management, mount syscalls, and native dialogs.
- **Rust → rclone:** Process spawning and lifecycle management only.

### Project Structure

```
streamcloned/
├── src/                          # React frontend
│   ├── app/                      # App shell, routing, providers
│   │   ├── App.tsx               # Root component
│   │   ├── router.tsx            # Route definitions
│   │   └── providers.tsx         # QueryClient, Theme, etc.
│   ├── components/               # Shared UI components
│   │   ├── ui/                   # shadcn/ui base components
│   │   └── ...                   # App-level shared components
│   ├── features/                 # Feature modules
│   │   ├── remotes/              # Remote management
│   │   │   ├── components/       # Remote-specific UI
│   │   │   ├── hooks/            # Remote-specific hooks
│   │   │   └── index.ts          # Public API
│   │   ├── browser/              # File browser
│   │   ├── transfers/            # Transfer queue
│   │   ├── copy-sync/            # Copy & Sync operations
│   │   ├── mount/                # Mount manager
│   │   └── settings/             # App settings
│   ├── lib/                      # Shared utilities
│   │   ├── rclone/               # Rclone API client & types
│   │   ├── tauri/                # Tauri IPC wrappers
│   │   └── utils/                # General helpers
│   ├── stores/                   # Zustand stores
│   │   ├── app-store.ts          # UI preferences, theme
│   │   ├── transfer-store.ts     # Transfer queue state
│   │   └── mount-store.ts        # Mount state
│   └── types/                    # Shared TypeScript types
├── src-tauri/                    # Rust backend
│   ├── src/
│   │   ├── main.rs               # Tauri entry point
│   │   ├── lib.rs                # Command registration
│   │   ├── commands/             # Tauri IPC commands
│   │   │   ├── rclone.rs         # Daemon lifecycle
│   │   │   ├── mount.rs          # Mount/unmount
│   │   │   └── tray.rs           # System tray
│   │   └── utils/                # Rust helpers
│   ├── Cargo.toml
│   └── tauri.conf.json
├── public/                       # Static assets
│   └── provider-icons/           # Cloud provider SVGs
├── package.json
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
└── biome.json
```

---

## Rclone Integration

### Binary Management

- **Bundled by default:** Ship rclone binary inside the Tauri app bundle for each platform/arch.
- **BYOB supported:** Settings page allows pointing to an existing rclone binary on PATH or a custom path.
- **Detection flow:** On first launch → check bundled binary → check PATH → offer to download.

### Daemon Lifecycle

1. App startup → Rust spawns `rclone rcd --rc-no-auth` on `localhost:5572`
2. Frontend polls `/rc/noop` until daemon responds (with timeout)
3. All subsequent operations go through the HTTP API
4. App quit → Rust sends SIGTERM to daemon process, waits, then SIGKILL if needed

### Daemon Port Handling

Default port is 5572. On startup, Rust checks if the port is available:
- If free → bind to it
- If occupied → try ports 5573–5580
- Store the active port in the app store so the frontend connects to the right one
- Display the active port in Settings for transparency

### Authentication

For v1, the daemon runs on localhost with no auth (`--rc-no-auth`). This is safe because:
- Bound to 127.0.0.1 only (not exposed to network)
- Same security model as Rclone UI and rclone's own web GUI

---

## Rclone API Surface

The rclone RC (Remote Control) API is HTTP/JSON on `localhost:<port>`. All calls are POST with JSON body.

### Endpoints Used by Feature

| Feature | Endpoint | Purpose |
|---------|----------|---------|
| Health check | `rc/noop` | Verify daemon is alive |
| Remote list | `config/listremotes` | Get all configured remotes |
| Remote info | `config/dump` | Get all remote configs with parameters |
| Provider list | `config/providers` | List available cloud providers |
| Create remote | `config/create` | Create a new remote (simple) |
| Interactive config | `config/create` → `config/update` | Multi-step OAuth/interactive setup |
| Update remote | `config/update` | Modify remote parameters |
| Delete remote | `config/delete` | Remove a remote |
| List directory | `operations/list` | List files/folders at path (`fs`, `remote`, `opt.recurse`) |
| File info | `operations/stat` | Get single file metadata |
| Mkdir | `operations/mkdir` | Create directory |
| Delete file | `operations/deletefile` | Delete a single file |
| Purge dir | `operations/purge` | Delete directory and all contents |
| Move/rename | `operations/movefile` | Move or rename a file |
| Copy file | `operations/copyfile` | Copy a single file |
| Copy tree | `sync/copy` | Copy directory tree src → dest. Use `_async: true` to get job ID for tracking |
| Sync tree | `sync/sync` | Sync directory tree (deletes extra in dest). Use `_async: true` for job ID |
| Mount | `mount/mount` | Mount remote as local filesystem |
| Unmount | `mount/unmount` | Unmount a mounted remote |
| List mounts | `mount/listmounts` | Get all active mounts |
| Job status | `job/status` | Get status of a running async job |
| Job list | `job/list` | List all running jobs |
| Job stop | `job/stop` | Cancel a running job |
| Core stats | `core/stats` | Transfer speed, bytes, errors, current files |
| Core bwlimit | `core/bwlimit` | Get/set bandwidth limit |
| About remote | `operations/about` | Get storage space info for a remote |

### Response Types

TypeScript types will be hand-written in `src/lib/rclone/types.ts`, modeled from rclone's RC API documentation. Rclone does not publish an OpenAPI spec, so we define our own interfaces based on observed responses. The `rclone-sdk` npm package may be used as a reference but we own our types.

---

## Remote Configuration Flow

Rclone's remote setup is often multi-step and interactive (OAuth flows, conditional fields). The RC API models this as a state machine:

### Simple Remotes (S3, FTP, SFTP, local)

1. Call `config/create` with `name`, `type`, and `parameters`
2. Remote is immediately usable

### OAuth Remotes (Google Drive, Dropbox, OneDrive, etc.)

1. Call `config/create` with `name`, `type`, and `parameters`
2. Response may include `State` indicating more input is needed
3. If OAuth is required, rclone opens a browser for the OAuth flow
4. The app polls or waits for the OAuth callback to complete
5. Call `config/update` with the auth token/state to finalize

### UI Implementation

- **Provider picker screen** → select provider type
- **Config form** → dynamically rendered from provider's parameter schema (from `config/providers`)
- **OAuth step** → show "Waiting for authorization..." with a "Open Browser" button and a cancel option
- **Completion** → success toast, redirect to home screen
- **Error** → inline error message with retry option

The config form fields are rendered dynamically based on the provider's `Options` array from `config/providers`, which includes field names, types, defaults, help text, and whether they're required or advanced.

---

## Error Handling Strategy

### Error Categories

| Category | Example | User-Facing Behavior |
|----------|---------|---------------------|
| Daemon unavailable | Daemon crashed, port conflict | Banner: "Connection lost. Reconnecting..." with auto-retry (exponential backoff, max 30s). After 3 failures, show "Rclone is not responding" with Restart/Settings buttons |
| API error | Invalid path, permission denied | Toast notification with error message from rclone. Non-destructive — user can retry |
| Network error | Cloud provider unreachable, timeout | Toast: "Could not reach [provider]. Check your connection." Retry button on the failed operation |
| Auth error | OAuth token expired, invalid credentials | Modal: "Re-authorize [remote name]?" with button to re-run OAuth flow |
| File operation error | File not found, conflict, quota exceeded | Inline error on the specific file/transfer row. Does not block other operations |
| Mount failure | FUSE not installed, mount point busy | Toast with specific guidance: "Install macFUSE to enable mounting" or "Mount point /Volumes/x is already in use" |

### Principles

- **Never silent failures.** Every error surfaces to the user.
- **Granular, not global.** One failed file doesn't kill the whole transfer. One failed mount doesn't block the app.
- **Actionable messages.** Every error tells the user what to do next (retry, re-auth, check settings).
- **Auto-retry for transient errors.** Network timeouts and daemon reconnection use exponential backoff. File operation errors do not auto-retry.

---

## v1 Features

### 1. Onboarding & Rclone Setup

**First launch flow:**
1. Splash screen with app logo
2. Detect/verify rclone binary (bundled or system)
3. Start daemon, verify connection
4. Welcome screen → "Add your first remote" CTA
5. Guided remote setup → lands on home screen

**Returning launch:**
1. Start daemon in background
2. Show home screen immediately (optimistic)
3. Reconnect indicator if daemon is slow

### 2. Remote Management (Home Screen)

The home screen is a grid of remote cards.

**Remote card shows:**
- Provider icon (Google Drive, S3, Dropbox, etc.)
- Remote name
- Quick action buttons: Browse, Mount, Copy To, Sync

**Operations:**
- Add remote: Opens provider picker → rclone's interactive config flow (via `config/create` API)
- Edit remote: Modify config parameters
- Delete remote: Confirmation dialog → `config/delete`
- Refresh: Re-fetch remote list

**Provider picker:** Grid of provider icons with search. Sourced from `config/providers` API endpoint.

### 3. File Browser

**Layout:**
- Breadcrumb path bar at top
- Toolbar: view toggle (grid/list), new folder, upload, search, sort
- File listing: icon, name, size, modified date
- Status bar: item count, selected count

**Operations:**
- Navigate: Click folder to enter, breadcrumb to go back
- Select: Click to select, Shift+click for range, Cmd/Ctrl+click for multi
- Create folder: Inline rename after creation
- Delete: Selected items → confirmation → `operations/deletefile` or `operations/purge`
- Rename: Inline edit → `operations/movefile`
- Download: Selected files → Tauri native save dialog (returns local path) → `operations/copyfile` from remote to local path via rclone (rclone treats local filesystem as a remote)
- Upload: Tauri open dialog or drag-and-drop (Tauri provides dropped file paths) → `operations/copyfile` from local path to remote via rclone
- Preview: Click file → side panel with image/text/media preview
- Search: Client-side filter of current directory listing only (not recursive). Search bar is labeled "Filter this folder" to set correct expectations. Recursive search is a v2 feature.

**View modes:**
- List: Compact rows with columns (name, size, date)
- Grid: Thumbnail cards (icons for non-image files)

### 4. Copy & Sync

**UI: Source → Destination picker**
- Left side: Source remote + path (with browse button)
- Right side: Destination remote + path (with browse button)
- Operation toggle: Copy or Sync
- Options panel (collapsible): include/exclude filters, dry run toggle, bandwidth limit

**Execution:**
- "Start" → calls `sync/copy` or `sync/sync` via rclone API
- Creates a transfer job tracked in the Transfer Queue
- Redirects to Transfer Queue with the new job highlighted

**Dry Run:**
- Toggle dry run → executes with `--dry-run` flag
- Shows preview of what would be copied/synced/deleted
- User confirms → re-runs without dry run

### 5. Transfer Queue

**Single view for all operations:**
- Active transfers: progress bar, speed, ETA, file count
- Queued: waiting to start (respects concurrent transfer limit)
- Completed: success/failure status, summary stats
- Each entry: operation type icon, source → dest, progress, action buttons

**Controls:**
- Cancel: Stop a running job via `job/stop`. Cancelled jobs move to the "completed" section with a "cancelled" status.
- Retry failed: Re-queue a failed or cancelled transfer by re-issuing the original API call with the same parameters.
- Clear completed: Remove finished/failed/cancelled entries from the list.
- **No pause/resume in v1.** Rclone's RC API does not support true pause/resume for async jobs. `job/stop` is terminal — the job cannot be restarted. Bandwidth throttling (`core/bwlimit` set to 0) simulates a pause but has global scope (affects all transfers). True per-job pause is a v2 goal that may require Rust-side transfer orchestration.

**Persistence:**
- Transfer history saved to Zustand persisted store
- Survives app restart (completed/failed history)
- Active transfers are re-evaluated on restart (not auto-resumed in v1)

### 6. Mount Manager

**Mount list view:**
- Each mount: remote name, local mount point, status (mounted/unmounted), VFS mode
- Toggle mount/unmount per entry
- "Auto-mount on startup" toggle per entry

**Add mount:**
- Pick remote → pick local mount point (native folder dialog)
- VFS mode: read-only or read-write
- Optional: cache settings (minimal for v1)

**Platform specifics (handled in Rust):**
- macOS: FUSE (macFUSE or FUSE-T) — detect and prompt for install if missing
- Windows: WinFsp — detect and prompt
- Linux: FUSE3 — typically available

**Auto-mount failure handling:**
- On startup, auto-mount attempts run sequentially
- If a mount fails: log the error, show a toast notification ("Failed to mount [name]: [reason]"), continue with remaining mounts
- Failed auto-mounts are marked with an error badge in the mount list
- Common failures and their messages: FUSE not installed → "Install macFUSE/WinFsp to enable mounting"; credentials expired → "Re-authorize [remote] to mount"; mount point busy → "Mount point is already in use"

**System tray integration:**
- Mounted remotes shown in tray menu
- Click to unmount
- Mount status icon indicators

### 7. System Tray

**Tray menu structure:**
```
StreamCloned
──────────────
Mounts
  ├── GoogleDrive → /Volumes/gdrive  [Unmount]
  └── S3Bucket → /Volumes/s3         [Unmount]
──────────────
Transfers: 2 active
──────────────
Open StreamCloned
Quit
```

**Behavior:**
- App close → minimize to tray (configurable: quit or minimize)
- Tray icon shows transfer activity indicator
- Click tray icon → show/focus main window

### 8. Settings

**Sections:**

- **Appearance:** Theme (light/dark/system)
- **Rclone:** Binary path, daemon port, auto-start on boot
- **Transfers:** Concurrent transfer limit, bandwidth limit (global)
- **Mounts:** Default VFS mode, default cache dir
- **About:** App version, rclone version, links to docs/repo

**Storage:** Zustand persisted store → Tauri's plugin-store (JSON file on disk)

---

## State Management Strategy

### Zustand Stores (Client State)

- **appStore:** Theme, sidebar collapsed, window state, settings
- **transferStore:** Active/queued/completed transfers, persisted
- **mountStore:** Mount configurations, auto-mount list, persisted

### TanStack Query (Server State)

- **Remote list:** `queryKey: ['remotes']` — refetch on mount, after config changes
- **File listing:** `queryKey: ['files', remote, path]` — cached per directory, invalidate on mutation
- **Transfer status:** `queryKey: ['transfers']` — polling interval during active transfers (2s), idle otherwise (30s)
- **Rclone stats:** `queryKey: ['stats']` — speed, bytes transferred, current file

### Why This Split

Zustand owns what the user has configured (preferences, mount list, transfer history). TanStack Query owns what rclone reports (file listings, transfer progress, remote config). Clean separation — no state duplication.

---

## Design Language

### Principles

- **Clean over clever:** No gratuitous animations. Purposeful motion only.
- **Information density:** Show useful data, not decorative chrome.
- **Keyboard-first:** Every action reachable via keyboard shortcut.
- **Platform-respectful:** Follow OS conventions for window chrome, dialogs, shortcuts.

### Visual Direction

- Neutral color palette with a single accent color
- Monospace for paths and technical values
- Sidebar navigation (remotes, browser, transfers, mounts, settings)
- Content area takes 80%+ of screen real estate
- Compact by default, not spacious — this is a power tool

---

## Non-Goals for v1

- Dual-panel commander / file manager
- Cron scheduling / recurring tasks
- Serve command (HTTP/FTP/WebDAV exposure)
- Templates / saved command configurations
- Multi-host / remote daemon management
- Bisync (two-way sync)
- Mobile companion
- Config encryption UI
- Proxy configuration
- Deep linking / URL scheme

---

## Open Questions

1. **License:** MIT vs Apache-2.0 vs AGPLv3 — needs decision before first public commit
2. **App name:** "StreamCloned" is a working codename. Final name TBD.
3. **FUSE dependency:** macOS and Windows require third-party FUSE drivers for mounting. How aggressive should onboarding be about prompting for install?
4. **Rclone version pinning:** Bundle a specific rclone version or always grab latest?
