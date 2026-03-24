# NFS Mounting (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace macFUSE-dependent mounting on macOS with `rclone serve nfs` + native NFS mount, requiring zero third-party dependencies.

**Architecture:** Each mount spawns a dedicated `rclone serve nfs` process on a localhost port, then mounts it via a bundled Swift CLI helper (NetFS framework) or `osascript` fallback. A Rust mount manager tracks all NFS server processes and mount state. The existing frontend mount UI routes to either NFS (macOS) or FUSE (Linux/Windows) based on platform detection.

**Tech Stack:** Rust (Tauri 2 commands), Swift (NetFS helper CLI), TypeScript/React (frontend hooks/store updates)

**Spec:** `docs/superpowers/specs/2026-03-24-nfs-mount-and-file-provider-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `src-tauri/src/commands/nfs_mount.rs` | Rust NFS mount manager — spawn `rclone serve nfs`, mount/unmount via Swift helper, track state per mount, health monitoring |
| `src-tauri/helpers/netfs-mount/main.swift` | Swift CLI helper — calls `NetFSMountURLSync` / `NetFSUnmountURLSync`, returns exit codes |
| `src-tauri/helpers/netfs-mount/build.sh` | Build script for the Swift helper |
| `src/lib/tauri/nfs-mount.ts` | TypeScript wrappers for new Tauri IPC commands (`nfs_mount`, `nfs_unmount`, `nfs_list_mounts`) |
| `src-tauri/Entitlements.plist` | macOS entitlements for network client/server |

### Modified Files

| File | Changes |
|------|---------|
| `src-tauri/src/commands/mod.rs` | Add `pub mod nfs_mount;` |
| `src-tauri/src/lib.rs` | Register NFS commands, add `NfsMountState`, fix `WindowEvent::Destroyed` to not kill rclone on window close |
| `src-tauri/build.rs` | Compile Swift helper during build on macOS |
| `src-tauri/Cargo.toml` | Add `dirs` crate for home directory, `tauri-plugin-os` for platform detection |
| `src-tauri/tauri.conf.json` | Add entitlements reference for macOS bundle, bundle Swift helper as resource |
| `src-tauri/capabilities/default.json` | Add `path:default` and `os:default` permissions |
| `src/stores/mount-store.ts` | Add `backend` field to `MountConfig` |
| `src/features/mount/hooks/use-mounts.ts` | Platform-aware mount/unmount — NFS on macOS, FUSE on others |
| `src/features/mount/components/add-mount-dialog.tsx` | Default mount point to `~/CloudDrives/{remoteName}`, add `backend` field |
| `src/features/mount/components/mount-item.tsx` | Route mount/unmount to correct backend |
| `src/features/mount/pages/mount-page.tsx` | Update active mount detection for NFS backend |

---

## Task 0: NetFS Privilege Spike

**Files:**
- Create: `src-tauri/helpers/netfs-mount/main.swift`

> **CRITICAL:** The spec notes that whether `NetFSMountURLSync` can mount NFS on localhost without root is **unverified**. This spike must run before any other task. If NetFS requires root for NFS, the `osascript` fallback becomes the primary path, which changes auto-mount UX.

- [ ] **Step 1: Write the Swift helper**

Create `src-tauri/helpers/netfs-mount/main.swift`:

```swift
import Foundation
import NetFS

// Usage:
//   netfs-mount mount  nfs://localhost:19049/ /path/to/mountpoint
//   netfs-mount unmount /path/to/mountpoint

let args = CommandLine.arguments

guard args.count >= 3 else {
    fputs("Usage: netfs-mount mount <url> <mountpoint> | unmount <mountpoint>\n", stderr)
    exit(1)
}

let action = args[1]

switch action {
case "mount":
    guard args.count >= 4 else {
        fputs("Usage: netfs-mount mount <url> <mountpoint>\n", stderr)
        exit(1)
    }
    let urlString = args[2]
    let mountPoint = args[3]

    guard let url = URL(string: urlString) else {
        fputs("Invalid URL: \(urlString)\n", stderr)
        exit(1)
    }

    let mountPath = URL(fileURLWithPath: mountPoint)

    // Create mount point directory if it doesn't exist
    try? FileManager.default.createDirectory(at: mountPath, withIntermediateDirectories: true)

    // Mount options for NFS
    // MNT_DONTBROWSE (0x00100000) prevents Spotlight indexing and Finder sidebar
    let openOptions: NSMutableDictionary = [:]
    let mountOptions: NSMutableDictionary = [
        "MNTOptionFlags": 0x00100000  // MNT_DONTBROWSE — matches nobrowse in mount_nfs fallback
    ]

    let result = NetFSMountURLSync(
        url as CFURL,
        mountPath as CFURL,
        nil,   // user
        nil,   // password
        openOptions as CFMutableDictionary,
        mountOptions as CFMutableDictionary,
        nil    // mountPoints
    )

    if result != 0 {
        fputs("Mount failed with error code: \(result)\n", stderr)
        // Print human-readable error
        let nsError = NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        fputs("Error: \(nsError.localizedDescription)\n", stderr)
        exit(Int32(result))
    }

    print("OK")

case "unmount":
    let mountPoint = args[2]
    let mountPath = URL(fileURLWithPath: mountPoint)

    let result = NetFSUnmountURLSync(
        mountPath as CFURL,
        0,     // flags
        nil    // unmountInfo
    )

    if result != 0 {
        fputs("Unmount failed with error code: \(result)\n", stderr)
        exit(Int32(result))
    }

    print("OK")

default:
    fputs("Unknown action: \(action). Use 'mount' or 'unmount'.\n", stderr)
    exit(1)
}
```

- [ ] **Step 2: Build the Swift helper**

```bash
mkdir -p src-tauri/helpers/netfs-mount
# (after writing main.swift)
swiftc src-tauri/helpers/netfs-mount/main.swift \
  -framework NetFS \
  -framework Foundation \
  -o src-tauri/helpers/netfs-mount/netfs-mount
```

- [ ] **Step 3: Test NetFS mounting manually**

Start rclone NFS server on a test remote (or local path) and test the helper:

```bash
# Terminal 1: Start rclone NFS server on a local path for testing
rclone serve nfs /tmp/nfs-test-data --addr localhost:19049

# Terminal 2: Test the helper
mkdir -p ~/CloudDrives/test
./src-tauri/helpers/netfs-mount/netfs-mount mount nfs://localhost:19049/ ~/CloudDrives/test
```

**Expected outcome:** Either mounts successfully (exit 0, prints "OK") or fails with a permission error. Document the result.

- [ ] **Step 4: Test unmount**

```bash
./src-tauri/helpers/netfs-mount/netfs-mount unmount ~/CloudDrives/test
```

- [ ] **Step 5: If NetFS fails without root, test osascript fallback**

```bash
osascript -e 'do shell script "mount_nfs -o nfsvers=3,tcp,nolocks,soft,timeo=50,nobrowse,nosuid,nodev,noresvport localhost:19049:/ /Users/$USER/CloudDrives/test" with administrator privileges'
```

- [ ] **Step 6: Document spike results**

Add a comment at the top of `main.swift` documenting:
- Whether NetFS worked without root
- macOS version tested on
- If osascript fallback was needed
- Any mount options that were required

- [ ] **Step 7: Commit**

```bash
git add src-tauri/helpers/netfs-mount/
git commit -m "spike: test NetFS framework for unprivileged NFS mounting"
```

---

## Task 1: Rust NFS Mount Manager — State & Port Allocation

**Files:**
- Create: `src-tauri/src/commands/nfs_mount.rs`
- Modify: `src-tauri/src/commands/mod.rs`

- [ ] **Step 1: Create the NFS mount state struct and port allocator**

Create `src-tauri/src/commands/nfs_mount.rs`:

```rust
use std::collections::HashMap;
use std::net::TcpListener;
use std::process::Child;
use std::sync::Mutex;

/// State for a single active NFS mount
pub struct MountEntry {
    pub remote: String,
    pub mount_point: String,
    pub port: u16,
    pub nfs_server: Child,
    pub method: MountMethod,
}

#[derive(Clone, Copy, PartialEq)]
pub enum MountMethod {
    NetFs,
    OsascriptSudo,
}

/// Global state tracking all active NFS mounts, keyed by mount point
pub struct NfsMountState {
    pub mounts: Mutex<HashMap<String, MountEntry>>,
}

impl Default for NfsMountState {
    fn default() -> Self {
        Self {
            mounts: Mutex::new(HashMap::new()),
        }
    }
}

/// On drop (app exit), kill all NFS server child processes.
/// This is a safety net for non-graceful exits (SIGTERM, panics).
/// Does NOT attempt unmount (which requires AppHandle) — stale mounts
/// are cleaned up on next startup via cleanup_stale_mounts.
impl Drop for NfsMountState {
    fn drop(&mut self) {
        if let Ok(mut mounts) = self.mounts.lock() {
            for (_, entry) in mounts.iter_mut() {
                let _ = entry.nfs_server.kill();
                let _ = entry.nfs_server.wait();
            }
        }
    }
}

const NFS_PORT_START: u16 = 19049;
const NFS_PORT_END: u16 = 19149;

/// Find an available port in the NFS range, excluding ports already in use by active mounts
pub fn find_nfs_port(active_ports: &[u16]) -> Option<u16> {
    for port in NFS_PORT_START..=NFS_PORT_END {
        if active_ports.contains(&port) {
            continue;
        }
        if TcpListener::bind(("127.0.0.1", port)).is_ok() {
            return Some(port);
        }
    }
    None
}
```

- [ ] **Step 2: Register module in mod.rs**

Modify `src-tauri/src/commands/mod.rs`:

```rust
pub mod nfs_mount;
pub mod rclone;
```

- [ ] **Step 3: Verify it compiles**

```bash
cd src-tauri && cargo check
```

Expected: compiles with no errors (warnings about unused code are fine)

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands/nfs_mount.rs src-tauri/src/commands/mod.rs
git commit -m "feat(nfs): add NFS mount state struct and port allocator"
```

---

## Task 2: Rust NFS Mount Manager — Spawn rclone serve nfs

**Files:**
- Modify: `src-tauri/src/commands/nfs_mount.rs`

- [ ] **Step 1: Add rclone version validation helper**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};

static NFS_SUPPORT_VALIDATED: AtomicBool = AtomicBool::new(false);

/// Check that rclone supports `serve nfs` (requires v1.62+).
/// Result is cached after first successful check.
pub fn validate_rclone_nfs_support() -> Result<(), String> {
    if NFS_SUPPORT_VALIDATED.load(Ordering::Relaxed) {
        return Ok(());
    }

    let output = Command::new("rclone")
        .args(["serve", "nfs", "--help"])
        .output()
        .map_err(|e| format!("Failed to run rclone: {}", e))?;

    if !output.status.success() {
        return Err(
            "rclone does not support 'serve nfs'. Please update to rclone v1.62 or later."
                .to_string(),
        );
    }

    NFS_SUPPORT_VALIDATED.store(true, Ordering::Relaxed);
    Ok(())
}
```

- [ ] **Step 2: Add spawn_nfs_server function**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
use std::time::{Duration, Instant};
use std::thread;

/// Spawn `rclone serve nfs` for a remote on the given port.
/// Waits up to 10 seconds for the server to be ready.
/// Uses tokio for async sleep to avoid blocking the Tauri runtime.
async fn spawn_nfs_server(remote: &str, port: u16, read_only: bool) -> Result<Child, String> {
    let mut args = vec![
        "serve".to_string(),
        "nfs".to_string(),
        remote.to_string(),
        "--addr".to_string(),
        format!("localhost:{}", port),
    ];

    if read_only {
        args.push("--read-only".to_string());
    } else {
        args.push("--vfs-cache-mode".to_string());
        args.push("writes".to_string());
    }

    let mut child = Command::new("rclone")
        .args(&args)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to start rclone serve nfs: {}", e))?;

    // Wait for the NFS server to be ready by probing the port
    let start = Instant::now();
    let timeout = Duration::from_secs(10);
    while start.elapsed() < timeout {
        if TcpListener::bind(("127.0.0.1", port)).is_err() {
            // Port is now in use by rclone — server is ready
            return Ok(child);
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    // Timeout — kill the orphaned process before returning error
    let _ = child.kill();
    let _ = child.wait();
    Err(format!(
        "rclone NFS server did not start within 10 seconds on port {}",
        port
    ))
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands/nfs_mount.rs
git commit -m "feat(nfs): add rclone NFS server spawning with readiness probe"
```

---

## Task 3: Swift NetFS Helper — Build Integration

**Files:**
- Create: `src-tauri/helpers/netfs-mount/build.sh`
- Modify: `src-tauri/build.rs`

The Swift helper from Task 0 needs to be compiled as part of the Tauri build on macOS.

- [ ] **Step 1: Create the build script for the Swift helper**

Create `src-tauri/helpers/netfs-mount/build.sh`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/netfs-mount"

# Only build on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping Swift helper build on non-macOS platform"
    exit 0
fi

# Skip if already built and source hasn't changed
if [[ -f "$OUTPUT" && "$OUTPUT" -nt "$SCRIPT_DIR/main.swift" ]]; then
    echo "Swift helper is up to date"
    exit 0
fi

echo "Building netfs-mount Swift helper..."
swiftc "$SCRIPT_DIR/main.swift" \
    -framework NetFS \
    -framework Foundation \
    -O \
    -o "$OUTPUT"

echo "Built: $OUTPUT"
```

- [ ] **Step 2: Make the build script executable**

```bash
chmod +x src-tauri/helpers/netfs-mount/build.sh
```

- [ ] **Step 3: Update build.rs to compile Swift helper on macOS**

Replace `src-tauri/build.rs` contents:

```rust
fn main() {
    tauri_build::build();

    // Build Swift NetFS helper on macOS
    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("bash")
            .arg("helpers/netfs-mount/build.sh")
            .status()
            .expect("Failed to run Swift helper build script");

        if !status.success() {
            panic!("Swift helper build failed");
        }

        // Tell Cargo to re-run if the Swift source changes
        println!("cargo:rerun-if-changed=helpers/netfs-mount/main.swift");
    }
}
```

- [ ] **Step 4: Verify the build compiles the helper**

```bash
cd src-tauri && cargo build 2>&1 | tail -5
ls -la helpers/netfs-mount/netfs-mount
```

Expected: binary exists at `src-tauri/helpers/netfs-mount/netfs-mount`

- [ ] **Step 5: Add the binary to .gitignore**

Append to the project root `.gitignore`:

```
src-tauri/helpers/netfs-mount/netfs-mount
```

- [ ] **Step 6: Commit**

```bash
git add src-tauri/helpers/netfs-mount/build.sh src-tauri/build.rs .gitignore
git commit -m "feat(nfs): integrate Swift NetFS helper into Tauri build"
```

---

## Task 4: Rust NFS Mount Manager — Mount & Unmount Commands

**Files:**
- Modify: `src-tauri/src/commands/nfs_mount.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add the mount helper invocation functions**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
use tauri::{AppHandle, Manager, State};
use std::path::PathBuf;

/// Resolve the path to the bundled netfs-mount helper.
/// In dev, it's at helpers/netfs-mount/netfs-mount relative to src-tauri/.
/// In production, it's bundled in the app's resource directory.
fn helper_path(app: &AppHandle) -> Result<PathBuf, String> {
    // Try resource path first (production)
    if let Ok(resource_dir) = app.path().resource_dir() {
        let prod_path = resource_dir.join("netfs-mount");
        if prod_path.exists() {
            return Ok(prod_path);
        }
    }

    // Fallback to dev path
    let dev_path = PathBuf::from("helpers/netfs-mount/netfs-mount");
    if dev_path.exists() {
        return Ok(dev_path);
    }

    Err("netfs-mount helper not found".to_string())
}

/// Mount an NFS share using the NetFS Swift helper.
/// Returns the mount method used.
/// NOTE: This function uses blocking I/O (process spawning). Callers in async
/// contexts must wrap calls in `tokio::task::spawn_blocking`.
fn mount_nfs_share(
    app: &AppHandle,
    port: u16,
    mount_point: &str,
) -> Result<MountMethod, String> {
    // Ensure mount point directory exists
    std::fs::create_dir_all(mount_point)
        .map_err(|e| format!("Failed to create mount point {}: {}", mount_point, e))?;

    // Try NetFS helper first
    let helper = helper_path(app)?;
    let url = format!("nfs://localhost:{}/", port);

    let output = Command::new(&helper)
        .args(["mount", &url, mount_point])
        .output()
        .map_err(|e| format!("Failed to run netfs-mount helper: {}", e))?;

    if output.status.success() {
        return Ok(MountMethod::NetFs);
    }

    // NetFS failed — fall back to osascript with admin privileges
    let stderr = String::from_utf8_lossy(&output.stderr);
    eprintln!("NetFS mount failed ({}), trying osascript fallback", stderr.trim());

    // Shell-escape the mount point to prevent injection
    let escaped_mp = mount_point.replace('\\', "\\\\").replace('"', "\\\"").replace('\'', "'\\''");
    let mount_cmd = format!(
        "mount_nfs -o nfsvers=3,tcp,nolocks,soft,timeo=50,nobrowse,nosuid,nodev,noresvport localhost:{}:/ '{}'",
        port, escaped_mp
    );

    let osa_output = Command::new("osascript")
        .args([
            "-e",
            &format!(
                "do shell script \"{}\" with administrator privileges",
                mount_cmd.replace('"', "\\\"")
            ),
        ])
        .output()
        .map_err(|e| format!("Failed to run osascript: {}", e))?;

    if osa_output.status.success() {
        return Ok(MountMethod::OsascriptSudo);
    }

    let osa_stderr = String::from_utf8_lossy(&osa_output.stderr);
    Err(format!("Mount failed: {}", osa_stderr.trim()))
}

/// Unmount an NFS share, using the method that matches how it was mounted.
fn unmount_nfs_share(app: &AppHandle, mount_point: &str, method: MountMethod) -> Result<(), String> {
    match method {
        MountMethod::NetFs => {
            let helper = helper_path(app)?;
            let output = Command::new(&helper)
                .args(["unmount", mount_point])
                .output()
                .map_err(|e| format!("Failed to run netfs-mount helper: {}", e))?;

            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(format!("Unmount failed: {}", stderr.trim()));
            }
        }
        MountMethod::OsascriptSudo => {
            let escaped_mp = mount_point.replace('\\', "\\\\").replace('"', "\\\"").replace('\'', "'\\''");
            let output = Command::new("osascript")
                .args([
                    "-e",
                    &format!(
                        "do shell script \"umount '{}'\" with administrator privileges",
                        escaped_mp
                    ),
                ])
                .output()
                .map_err(|e| format!("Failed to run osascript: {}", e))?;

            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(format!("Unmount failed: {}", stderr.trim()));
            }
        }
    }
    Ok(())
}
```

- [ ] **Step 2: Add the Tauri IPC commands**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
use serde::Serialize;

#[derive(Serialize, Clone)]
pub struct NfsMountInfo {
    pub remote: String,
    pub mount_point: String,
    pub port: u16,
}

#[tauri::command]
pub async fn nfs_mount(
    app: AppHandle,
    state: State<'_, NfsMountState>,
    remote: String,
    mount_point: String,
    read_only: bool,
) -> Result<(), String> {
    // Check rclone NFS support
    validate_rclone_nfs_support()?;

    let port = {
        let mounts = state.mounts.lock().unwrap();
        let active_ports: Vec<u16> = mounts.values().map(|m| m.port).collect();
        find_nfs_port(&active_ports)
            .ok_or_else(|| format!("No available port in range {}-{}", NFS_PORT_START, NFS_PORT_END))?
    };

    // Spawn rclone NFS server (uses async sleep for readiness probe)
    let child = spawn_nfs_server(&remote, port, read_only).await?;

    // Mount the NFS share (blocking I/O — run on blocking thread)
    let app_clone = app.clone();
    let mp_clone = mount_point.clone();
    let method = match tokio::task::spawn_blocking(move || {
        mount_nfs_share(&app_clone, port, &mp_clone)
    })
    .await
    .map_err(|e| format!("Mount task panicked: {}", e))?
    {
        Ok(m) => m,
        Err(e) => {
            // Kill the NFS server if mount failed
            let mut child = child;
            let _ = child.kill();
            let _ = child.wait();
            return Err(e);
        }
    };

    // Track the mount
    let entry = MountEntry {
        remote: remote.clone(),
        mount_point: mount_point.clone(),
        port,
        nfs_server: child,
        method,
    };
    state.mounts.lock().unwrap().insert(mount_point, entry);

    Ok(())
}

#[tauri::command]
pub async fn nfs_unmount(
    app: AppHandle,
    state: State<'_, NfsMountState>,
    mount_point: String,
) -> Result<(), String> {
    let entry = state
        .mounts
        .lock()
        .unwrap()
        .remove(&mount_point);

    match entry {
        Some(mut entry) => {
            // Unmount first (blocking I/O — run on blocking thread)
            let app_clone = app.clone();
            let mp_clone = entry.mount_point.clone();
            let method = entry.method;
            let unmount_result = tokio::task::spawn_blocking(move || {
                unmount_nfs_share(&app_clone, &mp_clone, method)
            })
            .await
            .map_err(|e| format!("Unmount task panicked: {}", e))?;

            // Always kill the NFS server, even if unmount failed
            let _ = entry.nfs_server.kill();
            let _ = entry.nfs_server.wait();

            unmount_result
        }
        None => Err(format!("No active NFS mount at {}", mount_point)),
    }
}

#[tauri::command]
pub fn nfs_list_mounts(state: State<'_, NfsMountState>) -> Vec<NfsMountInfo> {
    state
        .mounts
        .lock()
        .unwrap()
        .values()
        .map(|entry| NfsMountInfo {
            remote: entry.remote.clone(),
            mount_point: entry.mount_point.clone(),
            port: entry.port,
        })
        .collect()
}
```

- [ ] **Step 3: Register state and commands in lib.rs**

Replace `src-tauri/src/lib.rs`:

```rust
mod commands;
mod tray;
use commands::nfs_mount::NfsMountState;
use commands::rclone::RcloneState;
use tauri::{Manager, State};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(RcloneState::default())
        .manage(NfsMountState::default())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_os::init())
        .invoke_handler(tauri::generate_handler![
            commands::rclone::start_rclone,
            commands::rclone::stop_rclone,
            commands::rclone::get_rclone_port,
            commands::rclone::is_rclone_running,
            commands::nfs_mount::nfs_mount,
            commands::nfs_mount::nfs_unmount,
            commands::nfs_mount::nfs_list_mounts,
        ])
        .setup(|app| {
            tray::setup_tray(app)?;

            // Clean up stale NFS mounts from a previous crash.
            // Read known mount points from the persisted store (~/CloudDrives/*).
            // For now, clean up any localhost NFS mounts under ~/CloudDrives/.
            let home = dirs::home_dir().unwrap_or_default();
            let cloud_drives = home.join("CloudDrives");
            if cloud_drives.exists() {
                if let Ok(entries) = std::fs::read_dir(&cloud_drives) {
                    let mount_points: Vec<String> = entries
                        .filter_map(|e| e.ok())
                        .map(|e| e.path().to_string_lossy().to_string())
                        .collect();
                    commands::nfs_mount::cleanup_stale_mounts(&mount_points);
                }
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            // Only clean up on actual app exit, not window close.
            // The tray keeps the app alive — mounts should persist
            // while the tray is active.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                // Hide the window instead of destroying it
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

> **Note:** The `WindowEvent::Destroyed` handler that killed rclone is replaced with `CloseRequested` that hides the window. Cleanup happens via: (1) tray "Quit" handler calls `cleanup_all_mounts`, (2) `NfsMountState` `Drop` impl kills child processes on any exit path, (3) stale mounts from crashes are cleaned up on next startup in the `setup` hook.

> **Dependency:** Add `dirs = "5"` to `src-tauri/Cargo.toml` for `dirs::home_dir()`.

- [ ] **Step 4: Verify it compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/commands/nfs_mount.rs src-tauri/src/lib.rs
git commit -m "feat(nfs): add mount/unmount/list Tauri IPC commands with NetFS + osascript fallback"
```

---

## Task 5: Cleanup on App Exit

**Files:**
- Modify: `src-tauri/src/commands/nfs_mount.rs`
- Modify: `src-tauri/src/lib.rs`

The NFS server processes and mounts must be cleaned up when the app actually exits (via tray "Quit" or system shutdown).

- [ ] **Step 1: Add cleanup function to nfs_mount.rs**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
/// Clean up all active NFS mounts — kill servers and unmount.
/// Called on app exit. Best-effort: logs errors but doesn't fail.
pub fn cleanup_all_mounts(app: &AppHandle, state: &NfsMountState) {
    let mut mounts = state.mounts.lock().unwrap();
    for (_, mut entry) in mounts.drain() {
        // Try to unmount
        if let Err(e) = unmount_nfs_share(app, &entry.mount_point, entry.method) {
            eprintln!("Failed to unmount {}: {}", entry.mount_point, e);
        }
        // Kill NFS server
        let _ = entry.nfs_server.kill();
        let _ = entry.nfs_server.wait();
    }
}
```

- [ ] **Step 2: Add stale mount detection**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
/// Detect and clean up stale NFS mounts from a previous crash.
/// Checks `mount` output for localhost NFS mounts at known mount points.
/// Uses a 5-second timeout on unmount to avoid hanging on dead NFS servers.
pub fn cleanup_stale_mounts(mount_points: &[String]) {
    let output = match Command::new("mount").output() {
        Ok(o) => o,
        Err(_) => return,
    };

    let mount_output = String::from_utf8_lossy(&output.stdout);

    for line in mount_output.lines() {
        // Look for NFS mounts from localhost
        if !line.contains("localhost") || !line.contains("nfs") {
            continue;
        }

        for mp in mount_points {
            if line.contains(mp.as_str()) {
                eprintln!("Detected stale NFS mount at {}, cleaning up...", mp);
                // Best-effort unmount with 5-second timeout
                let child = Command::new("diskutil")
                    .args(["unmount", mp])
                    .spawn();
                if let Ok(mut child) = child {
                    let start = Instant::now();
                    loop {
                        match child.try_wait() {
                            Ok(Some(_)) => break,
                            Ok(None) => {
                                if start.elapsed() > Duration::from_secs(5) {
                                    eprintln!("Unmount timed out for {}, force killing", mp);
                                    let _ = child.kill();
                                    let _ = child.wait();
                                    // Force unmount as last resort
                                    let _ = Command::new("diskutil")
                                        .args(["unmount", "force", mp])
                                        .output();
                                    break;
                                }
                                thread::sleep(Duration::from_millis(100));
                            }
                            Err(_) => break,
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire cleanup into tray quit**

Modify `src-tauri/src/tray.rs` — update the "quit" handler to clean up mounts before exiting:

```rust
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

use crate::commands::nfs_mount::{cleanup_all_mounts, NfsMountState};
use crate::commands::rclone::RcloneState;

pub fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "Open StreamCloned", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &separator, &quit])?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            "quit" => {
                // Clean up NFS mounts
                let nfs_state: tauri::State<NfsMountState> = app.state();
                cleanup_all_mounts(app, nfs_state.inner());

                // Kill rclone daemon
                let rclone_state: tauri::State<RcloneState> = app.state();
                if let Some(mut child) = rclone_state.child.lock().unwrap().take() {
                    let _ = child.kill();
                    let _ = child.wait();
                }

                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
        })
        .build(app)?;
    Ok(())
}
```

- [ ] **Step 4: Verify it compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/commands/nfs_mount.rs src-tauri/src/tray.rs src-tauri/src/lib.rs
git commit -m "feat(nfs): add cleanup on app exit and stale mount detection"
```

---

## Task 6: macOS Entitlements

**Files:**
- Create: `src-tauri/Entitlements.plist`
- Modify: `src-tauri/tauri.conf.json`

- [ ] **Step 1: Create the entitlements file**

Create `src-tauri/Entitlements.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Reference entitlements in tauri.conf.json**

Add to the `bundle` section of `src-tauri/tauri.conf.json`:

```json
{
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "macOS": {
      "entitlements": "Entitlements.plist"
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add src-tauri/Entitlements.plist src-tauri/tauri.conf.json
git commit -m "feat(nfs): add macOS entitlements for network client/server"
```

---

## Task 7: TypeScript Tauri IPC Wrappers

**Files:**
- Create: `src/lib/tauri/nfs-mount.ts`

- [ ] **Step 1: Create the NFS mount IPC wrappers**

Create `src/lib/tauri/nfs-mount.ts`:

```typescript
import { invoke } from "@tauri-apps/api/core";

export interface NfsMountInfo {
  remote: string;
  mount_point: string;
  port: number;
}

export async function nfsMount(
  remote: string,
  mountPoint: string,
  readOnly: boolean,
): Promise<void> {
  return invoke<void>("nfs_mount", {
    remote,
    mountPoint,
    readOnly,
  });
}

export async function nfsUnmount(mountPoint: string): Promise<void> {
  return invoke<void>("nfs_unmount", { mountPoint });
}

export async function nfsListMounts(): Promise<NfsMountInfo[]> {
  return invoke<NfsMountInfo[]>("nfs_list_mounts");
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lib/tauri/nfs-mount.ts
git commit -m "feat(nfs): add TypeScript IPC wrappers for NFS mount commands"
```

---

## Task 8: Update Mount Store — Add Backend Field

**Files:**
- Modify: `src/stores/mount-store.ts`

- [ ] **Step 1: Add the backend field to MountConfig**

Update `src/stores/mount-store.ts`:

```typescript
import { create } from "zustand";
import { persist } from "zustand/middleware";

export type VfsMode = "read-only" | "read-write";
export type MountBackend = "nfs" | "fuse" | "fileprovider";

export interface MountConfig {
  remote: string;
  mountPoint: string;
  vfsMode: VfsMode;
  autoMount: boolean;
  backend: MountBackend;
}

interface MountState {
  configs: MountConfig[];
  addConfig: (config: MountConfig) => void;
  removeConfig: (mountPoint: string) => void;
  toggleAutoMount: (mountPoint: string) => void;
}

export const useMountStore = create<MountState>()(
  persist(
    (set) => ({
      configs: [],

      addConfig: (config) =>
        set((state) => ({
          configs: [...state.configs, config],
        })),

      removeConfig: (mountPoint) =>
        set((state) => ({
          configs: state.configs.filter((c) => c.mountPoint !== mountPoint),
        })),

      toggleAutoMount: (mountPoint) =>
        set((state) => ({
          configs: state.configs.map((c) =>
            c.mountPoint === mountPoint ? { ...c, autoMount: !c.autoMount } : c,
          ),
        })),
    }),
    {
      name: "streamcloned-mounts",
      // Migrate old configs without backend field
      migrate: (persistedState: unknown) => {
        const state = persistedState as MountState;
        if (state?.configs) {
          state.configs = state.configs.map((c) => ({
            ...c,
            backend: c.backend ?? "fuse",
          }));
        }
        return state;
      },
      version: 1,
    },
  ),
);
```

- [ ] **Step 2: Commit**

```bash
git add src/stores/mount-store.ts
git commit -m "feat(nfs): add backend field to MountConfig with migration for existing configs"
```

---

## Task 9: Platform Detection Utility

**Files:**
- Create: `src/lib/platform.ts`

- [ ] **Step 1: Create platform detection helper**

Create `src/lib/platform.ts`:

```typescript
import { platform } from "@tauri-apps/plugin-os";

export type Platform = "macos" | "linux" | "windows" | "unknown";

let cachedPlatform: Platform | null = null;

export function getPlatform(): Platform {
  if (cachedPlatform) return cachedPlatform;

  try {
    const p = platform();
    if (p === "macos") cachedPlatform = "macos";
    else if (p === "linux") cachedPlatform = "linux";
    else if (p === "windows") cachedPlatform = "windows";
    else cachedPlatform = "unknown";
  } catch {
    // Fallback for browser dev environment
    cachedPlatform = "unknown";
  }

  return cachedPlatform;
}

export function getDefaultMountBackend(): "nfs" | "fuse" {
  return getPlatform() === "macos" ? "nfs" : "fuse";
}
```

- [ ] **Step 2: Add the os plugin dependency if not present**

Check if `@tauri-apps/plugin-os` is installed:

```bash
grep "plugin-os" package.json || npm install @tauri-apps/plugin-os
```

Also add the Rust plugin if needed:

```bash
grep "tauri-plugin-os" src-tauri/Cargo.toml || (cd src-tauri && cargo add tauri-plugin-os@2)
```

Register it in `lib.rs` — add `.plugin(tauri_plugin_os::init())` after the other plugin registrations. The capability permissions (`"os:default"`, `"path:default"`) are added in Task 14.

- [ ] **Step 3: Commit**

```bash
git add src/lib/platform.ts package.json package-lock.json src-tauri/Cargo.toml src-tauri/src/lib.rs src-tauri/capabilities/default.json
git commit -m "feat(nfs): add platform detection utility for mount backend selection"
```

---

## Task 10: Update Mount Hooks — Platform-Aware Mount/Unmount

**Files:**
- Modify: `src/features/mount/hooks/use-mounts.ts`

- [ ] **Step 1: Rewrite hooks to route by backend**

Replace `src/features/mount/hooks/use-mounts.ts`:

```typescript
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listMounts, mountRemote, unmountRemote } from "@/lib/rclone/mount";
import { nfsListMounts, nfsMount, nfsUnmount } from "@/lib/tauri/nfs-mount";
import type { MountBackend } from "@/stores/mount-store";

export function useActiveMounts(backend: MountBackend) {
  return useQuery({
    queryKey: ["mounts", backend],
    queryFn: async () => {
      if (backend === "nfs") {
        const mounts = await nfsListMounts();
        return mounts.map((m) => ({
          Fs: m.remote,
          MountPoint: m.mount_point,
          MountedOn: m.mount_point,
        }));
      }
      // FUSE backend — use rclone RC API
      return listMounts();
    },
    refetchInterval: 10_000,
  });
}

export function useMountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      fs,
      mountPoint,
      vfsOpt,
      backend,
    }: {
      fs: string;
      mountPoint: string;
      vfsOpt?: Record<string, unknown>;
      backend: MountBackend;
    }) => {
      if (backend === "nfs") {
        const readOnly = vfsOpt?.readOnly === true;
        return nfsMount(fs, mountPoint, readOnly);
      }
      return mountRemote(fs, mountPoint, {}, vfsOpt);
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["mounts", variables.backend] });
    },
  });
}

export function useUnmountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      mountPoint,
      backend,
    }: {
      mountPoint: string;
      backend: MountBackend;
    }) => {
      if (backend === "nfs") {
        return nfsUnmount(mountPoint);
      }
      return unmountRemote(mountPoint);
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["mounts", variables.backend] });
    },
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add src/features/mount/hooks/use-mounts.ts
git commit -m "feat(nfs): make mount hooks platform-aware with NFS/FUSE routing"
```

---

## Task 11: Update Mount Page & Components

**Files:**
- Modify: `src/features/mount/pages/mount-page.tsx`
- Modify: `src/features/mount/components/mount-item.tsx`
- Modify: `src/features/mount/components/add-mount-dialog.tsx`

- [ ] **Step 1: Update MountPage to pass backend to useActiveMounts**

Replace `src/features/mount/pages/mount-page.tsx`:

```typescript
import { HardDriveIcon } from "lucide-react";
import { useMemo } from "react";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { getDefaultMountBackend } from "@/lib/platform";
import { useMountStore } from "@/stores/mount-store";
import { AddMountDialog } from "../components/add-mount-dialog";
import { MountItem } from "../components/mount-item";
import { useActiveMounts } from "../hooks/use-mounts";

export default function MountPage() {
  const configs = useMountStore((s) => s.configs);
  const defaultBackend = getDefaultMountBackend();
  const { data: activeMounts } = useActiveMounts(defaultBackend);

  const activeMountPoints = useMemo(() => {
    const set = new Set<string>();
    for (const m of activeMounts ?? []) {
      set.add(m.MountPoint);
    }
    return set;
  }, [activeMounts]);

  return (
    <div>
      <PageHeader
        title="Mounts"
        description="Mount remotes as local drives"
        actions={<AddMountDialog />}
      />
      <div className="p-6">
        {configs.length === 0 ? (
          <EmptyState
            icon={HardDriveIcon}
            title="No mounts configured"
            description="Add a mount to access your remote storage as a local drive."
            action={<AddMountDialog />}
          />
        ) : (
          <div className="grid gap-3">
            {configs.map((config) => (
              <MountItem
                key={config.mountPoint}
                config={config}
                isActive={activeMountPoints.has(config.mountPoint)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Update MountItem to pass backend to mutations**

Replace `src/features/mount/components/mount-item.tsx`:

```typescript
import { CircleIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { MountConfig } from "@/stores/mount-store";
import { useMountStore } from "@/stores/mount-store";
import { useMountRemote, useUnmountRemote } from "../hooks/use-mounts";

interface MountItemProps {
  config: MountConfig;
  isActive: boolean;
}

export function MountItem({ config, isActive }: MountItemProps) {
  const toggleAutoMount = useMountStore((s) => s.toggleAutoMount);
  const removeConfig = useMountStore((s) => s.removeConfig);
  const mountMutation = useMountRemote();
  const unmountMutation = useUnmountRemote();

  const isLoading = mountMutation.isPending || unmountMutation.isPending;

  function handleToggleMount() {
    if (isActive) {
      unmountMutation.mutate({
        mountPoint: config.mountPoint,
        backend: config.backend,
      });
    } else {
      mountMutation.mutate({
        fs: config.remote,
        mountPoint: config.mountPoint,
        vfsOpt: config.vfsMode === "read-only" ? { readOnly: true } : undefined,
        backend: config.backend,
      });
    }
  }

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4">
      <CircleIcon
        className={`size-3 shrink-0 ${isActive ? "fill-green-500 text-green-500" : "fill-muted text-muted"}`}
      />

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{config.remote}</p>
        <p className="text-xs text-muted-foreground font-mono truncate">
          {config.mountPoint}
        </p>
      </div>

      <label className="flex items-center gap-2 text-xs text-muted-foreground cursor-pointer select-none">
        <input
          type="checkbox"
          checked={config.autoMount}
          onChange={() => toggleAutoMount(config.mountPoint)}
          className="rounded"
        />
        Auto
      </label>

      <Button
        variant={isActive ? "destructive" : "outline"}
        size="sm"
        onClick={handleToggleMount}
        disabled={isLoading}
      >
        {isLoading ? (
          <Loader2Icon className="size-3.5 animate-spin" />
        ) : isActive ? (
          "Unmount"
        ) : (
          "Mount"
        )}
      </Button>

      <Button
        variant="ghost"
        size="sm"
        onClick={() => removeConfig(config.mountPoint)}
      >
        Remove
      </Button>
    </div>
  );
}
```

- [ ] **Step 3: Update AddMountDialog with default mount point and backend**

Replace `src/features/mount/components/add-mount-dialog.tsx`:

```typescript
import { open } from "@tauri-apps/plugin-dialog";
import { homeDir } from "@tauri-apps/api/path";
import { FolderOpenIcon, PlusIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useRemotes } from "@/features/remotes/hooks/use-remotes";
import { getDefaultMountBackend } from "@/lib/platform";
import { useMountStore, type VfsMode } from "@/stores/mount-store";

export function AddMountDialog() {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [remote, setRemote] = useState("");
  const [mountPoint, setMountPoint] = useState("");
  const [vfsMode, setVfsMode] = useState<VfsMode>("read-only");
  const [homePath, setHomePath] = useState("");

  const { data: remotes } = useRemotes();
  const addConfig = useMountStore((s) => s.addConfig);
  const backend = getDefaultMountBackend();

  // Get home directory for default mount point
  useEffect(() => {
    homeDir().then(setHomePath).catch(() => {});
  }, []);

  // Update default mount point when remote changes
  useEffect(() => {
    if (remote && homePath && backend === "nfs") {
      const remoteName = remote.replace(/:$/, "");
      setMountPoint(`${homePath}CloudDrives/${remoteName}`);
    }
  }, [remote, homePath, backend]);

  async function handleBrowse() {
    const selected = await open({ directory: true, multiple: false });
    if (selected) {
      setMountPoint(selected as string);
    }
  }

  function handleAdd() {
    if (!remote || !mountPoint) return;

    addConfig({
      remote: remote.endsWith(":") ? remote : `${remote}:`,
      mountPoint,
      vfsMode,
      autoMount: false,
      backend,
    });

    setRemote("");
    setMountPoint("");
    setVfsMode("read-only");
    setDialogOpen(false);
  }

  return (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogTrigger
        render={
          <Button>
            <PlusIcon data-icon="inline-start" />
            Add Mount
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Mount</DialogTitle>
          <DialogDescription>
            Mount a remote as a local drive on your system.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label>Remote</Label>
            <Select value={remote} onValueChange={(v) => setRemote(v ?? "")}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Select a remote" />
              </SelectTrigger>
              <SelectContent>
                {remotes?.map((r) => (
                  <SelectItem key={r.name} value={r.name}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-2">
            <Label>Mount Point</Label>
            <div className="flex gap-2">
              <Input
                value={mountPoint}
                onChange={(e) => setMountPoint(e.target.value)}
                placeholder={
                  backend === "nfs"
                    ? "~/CloudDrives/remote-name"
                    : "/mnt/remote"
                }
                className="flex-1 font-mono text-xs"
              />
              <Button variant="outline" size="icon" onClick={handleBrowse}>
                <FolderOpenIcon />
              </Button>
            </div>
          </div>

          <div className="grid gap-2">
            <Label>VFS Mode</Label>
            <Select
              value={vfsMode}
              onValueChange={(v) => setVfsMode(v as VfsMode)}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="read-only">Read Only</SelectItem>
                <SelectItem value="read-write">Read Write</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button onClick={handleAdd} disabled={!remote || !mountPoint}>
            Add
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Verify the frontend compiles**

```bash
npm run build
```

- [ ] **Step 5: Commit**

```bash
git add src/features/mount/pages/mount-page.tsx src/features/mount/components/mount-item.tsx src/features/mount/components/add-mount-dialog.tsx
git commit -m "feat(nfs): update mount UI with platform-aware backend routing and default mount points"
```

---

## Task 12: NFS Server Health Monitoring

**Files:**
- Modify: `src-tauri/src/commands/nfs_mount.rs`
- Modify: `src-tauri/src/lib.rs`

The spec requires: "Periodically check that the NFS server child process is still alive. If it crashes, proactively unmount the stale mount point and notify the user via toast."

- [ ] **Step 1: Add health check function**

Append to `src-tauri/src/commands/nfs_mount.rs`:

```rust
/// Check all active NFS server processes. If any have died,
/// unmount the stale mount point and remove from state.
/// Returns a list of mount points that were cleaned up.
pub fn check_nfs_health(app: &AppHandle, state: &NfsMountState) -> Vec<String> {
    let mut dead_mounts = Vec::new();
    let mut mounts = state.mounts.lock().unwrap();

    // First pass: detect dead processes
    let dead_keys: Vec<String> = mounts
        .iter_mut()
        .filter_map(|(key, entry)| {
            match entry.nfs_server.try_wait() {
                Ok(Some(_)) => Some(key.clone()), // Process exited
                Ok(None) => None,                  // Still running
                Err(_) => Some(key.clone()),       // Error checking — assume dead
            }
        })
        .collect();

    // Second pass: clean up dead mounts
    for key in dead_keys {
        if let Some(entry) = mounts.remove(&key) {
            eprintln!("NFS server died for mount {}", key);
            // Best-effort unmount
            let _ = unmount_nfs_share(app, &entry.mount_point, entry.method);
            dead_mounts.push(entry.mount_point);
        }
    }

    dead_mounts
}
```

- [ ] **Step 2: Add periodic health check in setup**

In `src-tauri/src/lib.rs`, add a spawned background task in the `setup` closure (after stale mount cleanup):

```rust
            // Spawn background health monitor for NFS servers
            let app_handle = app.handle().clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(10));
                    let nfs_state: State<NfsMountState> = app_handle.state();
                    let dead = commands::nfs_mount::check_nfs_health(&app_handle, nfs_state.inner());
                    for mp in &dead {
                        // Send notification about dead mount
                        eprintln!("NFS mount at {} was cleaned up due to server crash", mp);
                        // TODO: Send Tauri notification/event to frontend for toast
                    }
                }
            });
```

- [ ] **Step 3: Verify it compiles**

```bash
cd src-tauri && cargo check
```

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands/nfs_mount.rs src-tauri/src/lib.rs
git commit -m "feat(nfs): add periodic NFS server health monitoring"
```

---

## Task 13: Auto-Mount on Startup

**Files:**
- Modify: `src-tauri/src/commands/nfs_mount.rs`
- Create: `src/hooks/use-auto-mount.ts`
- Modify: `src/app/App.tsx`

Auto-mount is triggered from the frontend after the daemon connects, since the mount configs are stored in the frontend's Zustand store (persisted via localStorage).

- [ ] **Step 1: Add the auto-mount hook**

Create `src/hooks/use-auto-mount.ts`:

```typescript
import { useEffect, useRef } from "react";
import { getPlatform } from "@/lib/platform";
import { nfsMount } from "@/lib/tauri/nfs-mount";
import { mountRemote } from "@/lib/rclone/mount";
import { useMountStore } from "@/stores/mount-store";

/**
 * Auto-mounts all configs with autoMount: true on app startup.
 * Should be called once after the rclone daemon is connected.
 */
export function useAutoMount(daemonConnected: boolean) {
  const hasRun = useRef(false);
  const configs = useMountStore((s) => s.configs);

  useEffect(() => {
    if (!daemonConnected || hasRun.current) return;
    hasRun.current = true;

    const autoConfigs = configs.filter((c) => c.autoMount);
    if (autoConfigs.length === 0) return;

    const platform = getPlatform();

    // Mount sequentially to avoid port allocation races
    (async () => {
      for (const config of autoConfigs) {
        try {
          if (config.backend === "nfs" || (platform === "macos" && !config.backend)) {
            await nfsMount(
              config.remote,
              config.mountPoint,
              config.vfsMode === "read-only",
            );
          } else {
            await mountRemote(
              config.remote,
              config.mountPoint,
              {},
              config.vfsMode === "read-only" ? { readOnly: true } : undefined,
            );
          }
          console.log(`Auto-mounted ${config.remote} at ${config.mountPoint}`);
        } catch (e) {
          console.error(`Failed to auto-mount ${config.remote}:`, e);
        }
      }
    })();
  }, [daemonConnected, configs]);
}
```

- [ ] **Step 2: Wire into App.tsx**

Add the hook call in the main App layout, after the daemon connection is established. Check `src/app/App.tsx` and add:

```typescript
import { useAutoMount } from "@/hooks/use-auto-mount";

// Inside the component, after useDaemon():
useAutoMount(status === "connected");
```

- [ ] **Step 3: Verify the frontend compiles**

```bash
npm run build
```

- [ ] **Step 4: Commit**

```bash
git add src/hooks/use-auto-mount.ts src/app/App.tsx
git commit -m "feat(nfs): add auto-mount on startup for configs with autoMount enabled"
```

---

## Task 14: Bundle Swift Helper & Update Capabilities

**Files:**
- Modify: `src-tauri/tauri.conf.json`
- Modify: `src-tauri/capabilities/default.json`

The Swift helper binary needs to be included in the app bundle, and new permissions are needed for OS detection and path APIs.

- [ ] **Step 1: Update tauri.conf.json — entitlements + resources**

Replace the `bundle` section in `src-tauri/tauri.conf.json`:

```json
{
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "macOS": {
      "entitlements": "Entitlements.plist"
    },
    "resources": [
      "helpers/netfs-mount/netfs-mount"
    ]
  }
}
```

- [ ] **Step 2: Update capabilities/default.json — add os and path permissions**

Replace `src-tauri/capabilities/default.json`:

```json
{
  "identifier": "default",
  "description": "Default permissions for StreamCloned",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "shell:allow-execute",
    "shell:allow-spawn",
    "shell:allow-open",
    "dialog:allow-open",
    "dialog:allow-save",
    "dialog:allow-message",
    "dialog:allow-ask",
    "store:default",
    "http:default",
    "notification:default",
    "opener:default",
    "os:default",
    "path:default"
  ]
}
```

- [ ] **Step 3: Verify the full build works**

```bash
cd src-tauri && cargo build
```

- [ ] **Step 4: Commit**

```bash
git add src-tauri/tauri.conf.json src-tauri/capabilities/default.json
git commit -m "feat(nfs): bundle Swift helper, add os and path permissions"
```

---

## Task 15: Manual End-to-End Test

No code changes — this is a verification task.

- [ ] **Step 1: Start the dev server**

```bash
npm run tauri dev
```

- [ ] **Step 2: Add a test remote**

In the app, add a remote (any provider — even a local path remote works for testing).

- [ ] **Step 3: Add a mount config**

Go to Mounts → Add Mount. Verify:
- Remote dropdown shows available remotes
- Mount point pre-fills to `~/CloudDrives/{remoteName}` on macOS
- VFS mode selector works

- [ ] **Step 4: Mount the remote**

Click "Mount". Verify:
- The mount succeeds (green status indicator)
- The mount point directory exists
- `ls ~/CloudDrives/{remoteName}` shows the remote's files
- Files are accessible from Finder at that path

- [ ] **Step 5: Unmount the remote**

Click "Unmount". Verify:
- The mount point is no longer accessible
- The rclone NFS server process is killed
- Status indicator returns to inactive

- [ ] **Step 6: Test tray behavior**

- Close the main window (Cmd+W)
- Verify the mount stays active (`ls ~/CloudDrives/{remoteName}` still works)
- Click the tray icon → "Open StreamCloned" — window reappears
- Click tray → "Quit" — verify mount is cleaned up

- [ ] **Step 7: Test auto-mount**

- Enable "Auto" checkbox on a mount config
- Quit and relaunch the app
- Verify the mount is automatically activated on startup

- [ ] **Step 8: Document any issues found**

Record any issues in a new file or as GitHub issues for follow-up.
