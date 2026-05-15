# Nimbus: Swift/SwiftUI Native Rewrite

**Date:** 2026-03-31
**Status:** Draft
**Scope:** Full rewrite of the Nimbus macOS cloud storage manager from Tauri 2 (Rust + React + TypeScript) to native Swift/SwiftUI, retaining rclone as the cloud storage backend.

## Motivation

Three reinforcing problems with the current architecture:

1. **Non-native feel.** The Tauri/web layer produces a functional but noticeably non-native macOS experience — window chrome, focus behavior, drag-and-drop, and keyboard navigation all feel slightly off.
2. **Three-language complexity.** Maintaining TypeScript (6,600 LOC), Rust (780 LOC), and Swift (970 LOC) creates friction. The Rust layer exists primarily to bridge between the web frontend and macOS system APIs.
3. **Painful File Provider integration.** The extension communicates with the app through a JSON file in a shared app group container, and domain management requires shelling out to an embedded CLI tool — all because Rust can't call Apple's `NSFileProviderManager` API directly.

A native Swift/SwiftUI app eliminates all three problems simultaneously.

## Decisions

- **Keep rclone as backend.** Rclone supports 50+ cloud providers via its HTTP API. Reimplementing provider-specific networking is not justified.
- **Pure SwiftUI, with AppKit bridging as fallback.** Start with SwiftUI for all screens. If the file browser's `Table` view proves insufficient (outline views, advanced drag-and-drop), bridge to `NSOutlineView` via `NSViewRepresentable` for that one screen only.
- **Full rewrite, clean break.** No incremental migration. The current app is small enough (~8,300 LOC) that a clean rewrite is faster than trying to migrate layer by layer.
- **MVVM pattern.** SwiftUI views bind to `@Observable` view models. This maps directly to the current React hooks + components structure.

## Architecture

### Project structure

```
Nimbus/
├── Nimbus/                          # Main app target
│   ├── NimbusApp.swift              # @main, app lifecycle, MenuBarExtra
│   ├── Views/                       # SwiftUI views by feature
│   │   ├── Sidebar.swift
│   │   ├── Browser/
│   │   │   ├── BrowserView.swift
│   │   │   ├── FileTable.swift
│   │   │   ├── FileGrid.swift
│   │   │   ├── BrowserToolbar.swift
│   │   │   └── FileContextMenu.swift
│   │   ├── Remotes/
│   │   │   ├── RemotesView.swift
│   │   │   ├── RemoteRow.swift
│   │   │   ├── AddRemoteSheet.swift
│   │   │   ├── EditRemoteSheet.swift
│   │   │   └── ProviderPicker.swift
│   │   ├── Mounts/
│   │   │   ├── MountsView.swift
│   │   │   ├── MountRow.swift
│   │   │   └── AddMountSheet.swift
│   │   ├── Transfers/
│   │   │   ├── TransfersView.swift
│   │   │   └── TransferRow.swift
│   │   ├── CopySync/
│   │   │   ├── CopySyncView.swift
│   │   │   └── PathPicker.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   ├── AppearanceSection.swift
│   │   │   ├── TransferSection.swift
│   │   │   ├── RcloneSection.swift
│   │   │   └── AboutSection.swift
│   │   └── Onboarding/
│   │       └── OnboardingView.swift
│   ├── ViewModels/
│   │   ├── BrowserViewModel.swift
│   │   ├── RemotesViewModel.swift
│   │   ├── MountsViewModel.swift
│   │   ├── TransfersViewModel.swift
│   │   └── CopySyncViewModel.swift
│   ├── Services/
│   │   ├── RcloneDaemon.swift
│   │   ├── MountManager.swift
│   │   └── FileProviderBridge.swift
│   └── State/
│       ├── AppSettings.swift
│       └── MountConfiguration.swift
├── RcloneKit/                       # Local Swift Package
│   ├── Sources/RcloneKit/
│   │   ├── RcloneClient.swift
│   │   ├── Operations.swift
│   │   ├── Remotes.swift
│   │   ├── Sync.swift
│   │   ├── Jobs.swift
│   │   ├── Stats.swift
│   │   └── Models.swift
│   └── Tests/RcloneKitTests/
├── FileProviderExtension/           # Refactored extension target
│   ├── Extension.swift
│   ├── Enumerator.swift
│   └── Item.swift
└── Nimbus.xcodeproj
```

### Layer diagram

```
SwiftUI Views ←→ ViewModels ←→ Services (daemon, mount, file provider)
                      ↕
                  RcloneKit (shared Swift Package)
                      ↕
                Rclone Daemon (HTTP API on localhost)

FileProviderExtension → RcloneKit (same package, direct import)
```

No IPC boundary. No bridge. No CLI tools. Everything is in-process Swift (except the rclone subprocess).

## Component Design

### RcloneKit (shared Swift Package)

A typed HTTP client wrapping rclone's RC API. Used by both the main app and File Provider extension.

**RcloneClient.swift** — base HTTP layer:
- `URLSession`-based, `POST` to `http://localhost:{port}/{endpoint}`
- Async/await with `Codable` request/response types
- Custom `RcloneError` type
- Configurable port (set at init, updatable at runtime)

**Operations.swift** — file operations:
- `listFiles(fs:remote:)` → `operations/list`
- `stat(fs:remote:)` → `operations/stat`
- `mkdir(fs:remote:)` → `operations/mkdir`
- `deleteFile(fs:remote:)` → `operations/deletefile`
- `purge(fs:remote:)` → `operations/purge`
- `moveFile(src:dst:)` → `operations/movefile`
- `copyFile(src:dst:)` → `operations/copyfile`
- `about(fs:)` → `operations/about`

**Remotes.swift** — remote configuration:
- `listRemotes()` → `config/listremotes`
- `configDump()` → `config/dump`
- `getProviders()` → `config/providers`
- `createRemote(name:type:parameters:)` → `config/create`
- `updateRemote(name:parameters:)` → `config/update`
- `deleteRemote(name:)` → `config/delete`

**Sync.swift** — bulk operations:
- `copy(opts:)` → `sync/copy` (async, returns job ID)
- `sync(opts:)` → `sync/sync` (async, returns job ID)

**Jobs.swift** — job monitoring:
- `listJobs()` → `job/list`
- `jobStatus(id:)` → `job/status`
- `stopJob(id:)` → `job/stop`

**Stats.swift** — transfer statistics:
- `getStats()` → `core/stats`

**Models.swift** — shared Codable types:
- `FileItem` (path, size, modTime, isDir, mimeType)
- `Remote` (name, type, configuration dictionary)
- `Provider` (name, description, option schemas)
- `ProviderOption` (name, type, default, required, isPassword, examples)
- `Job` (id, finished, success, error, duration, output)
- `TransferStats` (speed, bytes, eta, percentage, transferring array)

### Services

**RcloneDaemon** — process lifecycle:
- Spawns `rclone rcd --rc-addr=localhost:{port} --rc-no-auth` via `Process`
- Scans ports 5572-5580 if occupied
- Health check: polls `rc/noop` via RcloneKit, up to 30 attempts at 500ms intervals
- Exposes `@Observable` properties: `isRunning`, `port`, `error`
- Terminates process on app quit via `applicationWillTerminate`

**MountManager** — NFS mount orchestration:
- `mount(remote:mountPoint:readOnly:)`:
  - Validate mount point (absolute, under home dir)
  - Allocate NFS port from range 19049-19149
  - Spawn `rclone serve nfs` via `Process`
  - Wait for NFS server ready (poll with timeout)
  - Execute `mount_nfs` via `Process`
- `unmount(mountPoint:)`:
  - `umount` with 5s timeout
  - Fallback to `diskutil unmount force`
  - Kill associated NFS server process
- Health monitor: `Task` polling every 10s for dead NFS servers
- Stale mount cleanup on app startup
- Tracks active mounts as `@Observable` array

**FileProviderBridge** — domain management via direct API:
- `addDomain(identifier:displayName:)` → `NSFileProviderManager.add(_:)`
- `removeDomain(identifier:)` → `NSFileProviderManager.remove(_:)`
- `listDomains()` → `NSFileProviderManager.getDomainsWithCompletionHandler`
- `syncState(remotes:port:)` → write port to app group `UserDefaults`
- `cleanupStaleDomains(activeRemotes:)` → diff registered vs. active, remove stale

Replaces: `fp-domain-manager` CLI tool, `commands/file_provider.rs` (183 LOC), shell invocation code. New size: ~40 LOC.

### State Management

**AppSettings** — `@Observable` class using `@AppStorage`:
- `rclonePort: Int` (default 5572)
- `rclonePath: String` (default `/usr/local/bin/rclone`)
- `bandwidthLimit: String`
- `concurrentTransfers: Int` (default 4)
- `onboardingComplete: Bool`
- `appearance: Appearance` (light/dark/system)
- `sidebarCollapsed: Bool`

**MountConfiguration** — `Codable` persisted to app support directory:
- Array of `MountConfig` structs: remote, mountPath, vfsMode, backend, autoMount
- Loaded on launch, saved on mutation
- Version field for future migration

**TransferStore** — `@Observable`, in-memory only:
- Active/completed/failed/cancelled `Transfer` records
- Each transfer: jobId, operation (copy/sync), source, destination, startTime, status, error
- Polling loop via `Task` calling `RcloneKit.Jobs.jobStatus()` every 1s for active transfers

**Shared state (app ↔ extension):**
- App group `UserDefaults(suiteName: "group.com.nimbus.app")`
- App writes: rclone port, active remote list
- Extension reads: constructs `RcloneClient(port:)` from stored port
- Replaces current `fileprovider-state.json` approach

### UI Screens

**App shell:**
- `NimbusApp.swift`: `@main` struct with `WindowGroup` + `MenuBarExtra`
- `NavigationSplitView` with sidebar (remotes, mounts, transfers, copy-sync, settings)
- Close button hides to dock (`.onDisappear` handling or `NSWindow` delegate)
- `MenuBarExtra` with "Show Nimbus" and "Quit" items

**Browser** (most complex):
- `BrowserView` — container with toolbar, breadcrumb, content area
- `FileTable` — `Table` view with sortable columns (name, size, date, type), multi-selection via `Table(selection:)`
- `FileGrid` — `LazyVGrid` with file icons/thumbnails
- `BrowserToolbar` — `toolbar {}` with view mode `Picker`, sort options, action buttons (upload, new folder)
- `FileContextMenu` — `.contextMenu {}` on each row/grid item: open, download, rename, copy, move, delete
- Inline rename via `TextField` with `@FocusState`
- View model caches file lists keyed by `(remote, path)` for back/forward navigation

**Remotes:**
- `RemotesView` — `List` of `RemoteRow` items with swipe actions (edit, delete)
- `AddRemoteSheet` — `ProviderPicker` → dynamic `Form` generated from provider option schema
- `EditRemoteSheet` — same dynamic form, pre-filled with current config
- Delete confirmation via `.alert()` or `.confirmationDialog()`

**Dynamic config form:**
- Iterate over provider's `ProviderOption` array from `RcloneKit.Remotes.getProviders()`
- Switch on option type to render: `TextField`, `SecureField` (passwords), `Toggle` (booleans), `Picker` (enums with examples), `TextEditor` (multiline)
- Show only required fields by default, expandable section for advanced options

**Mounts:**
- `MountsView` — `List` with toggle for active/inactive, mount path display
- `MountRow` — remote name, path, status indicator, mount/unmount button
- `AddMountSheet` — `Form` with remote picker, mount path, VFS mode, auto-mount toggle

**Transfers:**
- `TransfersView` — `List` grouped by status (active, completed, failed)
- `TransferRow` — operation icon, source → destination, `ProgressView`, speed/ETA, cancel button

**Copy-Sync:**
- `CopySyncView` — source and destination `PathPicker`, operation type toggle (copy/sync), start button
- `PathPicker` — remote picker + path browser (reuses file list loading from BrowserViewModel)

**Settings:**
- `Settings` scene (macOS native settings window) with `TabView`:
  - Appearance: color scheme picker
  - Transfers: bandwidth limit field, concurrent transfers stepper
  - Rclone: binary path, port
  - About: version, links

**Onboarding:**
- Multi-step flow: welcome → configure first remote → optional mount setup → done
- Sets `appSettings.onboardingComplete = true` on finish

### File Provider Extension (Refactored)

The existing extension stays structurally similar but gets simpler:

- **Import RcloneKit** directly instead of maintaining a separate `RcloneClient.swift`
- **Delete** `SharedState.swift` — read port from app group `UserDefaults` instead
- **Delete** `DomainManager.swift` — domain management is handled by the main app's `FileProviderBridge`
- **Keep** `Extension.swift`, `Enumerator.swift`, `Item.swift` with minor modifications to use RcloneKit types

Net change: ~970 LOC → ~700 LOC, with better type safety via shared models.

## Build & Distribution

### Xcode project structure

Single `.xcodeproj` with three targets:
1. **Nimbus** (app) — depends on RcloneKit package
2. **RcloneKit** (local Swift Package) — no dependencies beyond Foundation
3. **FileProviderExtension** (app extension) — depends on RcloneKit, embedded in Nimbus.app

Xcode handles extension embedding, code signing, and provisioning profiles natively. No `embed-extension.sh`, no XcodeGen, no post-build scripts.

### What gets deleted

| Component | Reason |
|-----------|--------|
| `src/` (all React/TS) | Replaced by SwiftUI views |
| `src-tauri/src/` (all Rust) | Replaced by Services layer |
| `src-tauri/Cargo.toml`, `Cargo.lock` | No Rust |
| `package.json`, `node_modules/`, `package-lock.json` | No Node.js |
| `vite.config.ts`, `tailwind.config.ts`, `tsconfig.json`, `biome.json` | No web tooling |
| `scripts/embed-extension.sh` | Xcode handles embedding |
| `src-tauri/FileProviderExtension/project.yml` | No XcodeGen |
| `fp-domain-manager` CLI tool | Direct `NSFileProviderManager` API |
| `src-tauri/FileProviderExtension/SharedState.swift` | App group UserDefaults |
| `src-tauri/FileProviderExtension/DomainManager.swift` | FileProviderBridge in main app |
| `src-tauri/tauri.conf.json` | No Tauri |

### npm scripts → equivalents

| Current | New |
|---------|-----|
| `npm run dev` | `Cmd+R` in Xcode (debug run) |
| `npm run build:release` | `Product > Archive` in Xcode |
| `npm run test` | `Cmd+U` in Xcode or `swift test` for RcloneKit |
| `npx biome check .` | SwiftLint (optional, or Xcode warnings) |

## Effort Estimate

| Phase | What | Est. LOC |
|-------|------|----------|
| 1 | RcloneKit Swift Package | ~600 |
| 2 | Services (daemon, mount, file provider) | ~350 |
| 3 | App shell (window, sidebar, nav, tray) | ~150 |
| 4 | Settings + Onboarding | ~200 |
| 5 | Remotes management | ~400 |
| 6 | File Browser | ~500 |
| 7 | Mounts UI | ~200 |
| 8 | Transfers + Copy-Sync | ~300 |
| 9 | File Provider extension refactor | ~100 (net deletion) |
| 10 | Polish (keyboard shortcuts, edge cases) | ~200 |
| **Total** | | **~3,000** |

Down from ~8,300 LOC across three languages. The reduction comes from:
- Eliminating the Rust bridge layer entirely
- SwiftUI being more concise than React + Tailwind + shadcn
- Direct `NSFileProviderManager` API replacing CLI tool + shell invocations
- Shared RcloneKit replacing duplicate HTTP clients
- Xcode handling what build scripts did

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| SwiftUI `Table` lacks outline/tree view for nested folders | Start with flat directory listing (current behavior). Bridge to `NSOutlineView` only if needed. |
| NFS mount management complexity is language-independent | Accept this. Port carefully, test thoroughly. Rust logic is the reference implementation. |
| Dynamic provider config forms may have edge cases | Test with the 5-6 most common providers (S3, Google Drive, OneDrive, Dropbox, SFTP, local). |
| Swift concurrency lifecycle (daemon → health → mount → file provider) | Sequential startup with clear error states. Model as a state machine. |
| Loss of cross-platform potential | Accepted tradeoff. Nimbus targets macOS only. |

## Testing Strategy

- **RcloneKit**: Unit tests with mocked URLSession responses. Integration tests against a real rclone instance.
- **Services**: Integration tests for daemon lifecycle, mount/unmount. These require a real rclone binary.
- **ViewModels**: Unit tests with mocked RcloneKit client.
- **UI**: Manual testing. SwiftUI previews for layout validation.
- **File Provider**: Manual testing via Finder. Verify enumeration, download, upload with a real remote.
