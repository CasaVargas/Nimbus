# NFS Mounting & Apple File Provider Design

## Problem

macFUSE on macOS Tahoe requires disabling SIP and enabling kernel extensions — unacceptable UX for a commercial app. FUSE-T is an alternative but requires a commercial license for bundling with commercial software. We need a mounting solution that is dependency-free, commercially safe, and provides full filesystem integration (Finder, third-party apps, CLI tools).

## Decision

Two-phase approach:

- **Phase 1 (v1):** Replace FUSE mounting on macOS with `rclone serve nfs` + native macOS NFS mount. No third-party dependencies. Linux/Windows continue using FUSE (FUSE3/WinFsp work fine).
- **Phase 2 (post-v1):** Apple File Provider Extension for first-class Finder integration on macOS. NFS remains as Linux path and macOS fallback.

## Licensing

- rclone: MIT license — fully commercial-friendly
- macOS NFS client: built into the OS
- Apple File Provider framework: standard macOS API
- No third-party dependencies with restrictive licenses

---

## Phase 1: rclone NFS Mounting

### Architecture

Instead of calling rclone's `mount/mount` RC endpoint (which needs FUSE), the app will:

1. Spawn `rclone serve nfs` on a localhost port per remote
2. Call `mount_nfs` via Tauri to mount the NFS share at the chosen path
3. Manage lifecycle — track NFS server processes alongside mount state

```
┌─────────────────────┐
│   Mount Manager UI   │  (existing, minor changes)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Rust Mount Manager  │  (new - replaces rclone mount/mount calls)
│  - spawn rclone     │
│    serve nfs         │
│  - call mount_nfs    │
│  - track processes   │
│  - auto-mount on     │
│    app start         │
└─────────────────────┘
          │
    ┌─────┴──────┐
    ▼            ▼
┌────────┐  ┌──────────┐
│ rclone │  │ macOS    │
│ serve  │  │ mount_nfs│
│ nfs    │  │ (native) │
│ :2049+ │  │          │
└────────┘  └──────────┘
```

### Rust Mount Manager

Per-mount, the Rust layer will:

- Allocate a localhost port (starting at 2049, incrementing per mount)
- Spawn `rclone serve nfs {remote}: --addr localhost:{port} --vfs-cache-mode writes`
- Wait for the NFS server to be ready (probe port, timeout after 10 seconds)
- Execute `mount -t nfs -o locallocks,nobrowse,nosuid,nodev localhost:/ {mountPoint}`
- Store the child process handle for cleanup

State tracked per mount:

- Remote name
- Mount point path
- NFS server port
- Child process handle
- VFS mode (read-only / read-write)

### New Tauri IPC Commands

| Command | Purpose |
|---------|---------|
| `nfs_mount(remote, mountPoint, vfsOpt)` | Spawn NFS server + mount |
| `nfs_unmount(mountPoint)` | Unmount + kill NFS server process |
| `nfs_list_mounts()` | Return active NFS mounts from Rust state |
| `nfs_auto_mount_all()` | Called on app start for auto-mount configs |

### Frontend Changes

Minimal — the mount manager UI stays almost the same:

- **Default mount point** changes from empty to `~/CloudDrives/{remoteName}` (pre-filled, editable)
- **Mount/Unmount buttons** call new Tauri IPC commands instead of rclone RC `mount/mount`
- **Platform detection** — on macOS, use the NFS approach. On Linux/Windows, keep using rclone's FUSE mount (FUSE3/WinFsp work fine)
- **Status polling** switches from rclone `mount/listmounts` to querying the Rust mount manager's state

The existing mount store (Zustand) stays unchanged — it already tracks remote, mountPoint, vfsMode, and autoMount.

### Default Mount Points

`~/CloudDrives/{remoteName}` — created automatically, user can override in the mount config dialog.

### Auto-Mount

On app start, iterate saved configs with `autoMount: true`, mount them in sequence. On app quit, unmount all and kill NFS server processes.

### Error Handling & Edge Cases

- **Port conflicts:** If a port is occupied, increment and retry (same pattern as existing rclone daemon port allocation in `rclone.rs`)
- **Stale mounts:** On app start, check if mount points are already mounted (leftover from a crash). Run `umount` before re-mounting.
- **NFS server health:** After spawning `rclone serve nfs`, probe the port before calling `mount_nfs`. Timeout after 10 seconds with an error toast.
- **Permissions:** `~/CloudDrives/` directory created with user permissions. No `sudo` needed for NFS localhost mounts on macOS.
- **App crash / force quit:** Mounts become stale. On next app start, detect and clean up before re-mounting auto-mount configs.
- **Finder metadata:** Pass `nobrowse` mount flag to prevent Spotlight indexing and `.DS_Store` pollution on cloud remotes. Users who want Finder sidebar visibility can toggle this off per mount.
- **VFS caching:** Passed through to `rclone serve nfs` via `--vfs-cache-mode` flag. Maps directly from the existing vfsMode config (read-only uses `--read-only`, read-write uses `--vfs-cache-mode writes`).

### Platform Strategy

| Platform | Mounting Backend | Dependencies |
|----------|-----------------|-------------|
| macOS | `rclone serve nfs` + native `mount_nfs` | None (NFS client built-in) |
| Linux | rclone `mount/mount` RC API | FUSE3 (usually pre-installed) |
| Windows | rclone `mount/mount` RC API | WinFsp |

---

## Phase 2: Apple File Provider Extension

### What It Gets You

- Files appear in Finder sidebar under "Locations" — same as iCloud, Dropbox, OneDrive
- On-demand download with progress badges (cloud icon, download arrow, checkmark)
- Right-click "Remove Download" / "Download Now" per file
- Spotlight search integration
- Works with any app — no mount points, no NFS, no dependencies
- Apple-blessed, future-proof across macOS updates

### Architecture

```
┌──────────────────────┐
│  StreamCloned App     │  (main Tauri app)
│  - manages remotes    │
│  - rclone daemon      │
│  - settings/UI        │
└──────────┬───────────┘
           │ XPC / shared state
           ▼
┌──────────────────────┐
│  File Provider Ext    │  (native Swift macOS App Extension)
│  - enumerates items   │
│  - materializes files │  (download on access)
│  - evicts files       │  (free local space)
│  - uploads changes    │
└──────────┬───────────┘
           │ HTTP/JSON
           ▼
┌──────────────────────┐
│  Rclone RC Daemon     │  (existing, unchanged)
└──────────────────────┘
```

The File Provider Extension is a separate Swift target that ships inside the app bundle. It communicates with rclone the same way the frontend does — HTTP calls to the RC daemon. The main app manages rclone lifecycle and remote configuration; the extension handles Finder integration.

### Key Implementation Pieces

- **NSFileProviderReplicatedExtension** — the modern API (replaces the deprecated enumeration-based one)
- **Domain per remote** — each configured remote becomes a File Provider domain (appears as its own location in Finder)
- **Item enumeration** — maps rclone `operations/list` to `NSFileProviderItem` objects
- **Materialization** — when a user opens a file, the extension downloads it via rclone `operations/copyfile` to a local staging area
- **Eviction** — Apple manages disk space automatically; the extension just deletes the local copy when told
- **Uploads** — when a user saves a file, the extension pushes changes back via rclone `operations/copyfile` in reverse
- **Shared state** — App Group container for the main app and extension to share rclone port, remote configs, auth state

### What Makes This Hard

- **Conflict resolution** — if a file changes both locally and remotely, you need merge/overwrite logic
- **Thumbnail & metadata providers** — optional but expected for good UX
- **Testing** — File Provider extensions are notoriously hard to debug (requires provisioning profile, entitlements, sometimes a restart)
- **Tauri integration** — the extension is a native Swift target that needs to coexist with the Tauri build system. Likely means a custom Xcode project alongside the Tauri Rust build

---

## Phasing & Migration

**v1 (ship now):** NFS mounting on macOS, FUSE mounting on Linux/Windows. Mount manager UI works the same across platforms — backend differs per OS.

**v2 (post-launch):** File Provider Extension on macOS. When enabled, it replaces NFS for Finder integration. NFS remains available as a fallback or for users who prefer traditional mount points.

**Migration path:** When File Provider lands, existing mount configs migrate automatically — same remote, same vfsMode, just a different backend. Users see their remotes appear in Finder sidebar instead of at a mount point path. A setting lets users choose "Finder integration (recommended)" vs "NFS mount (classic)" per remote.
