use std::collections::HashMap;
use std::net::TcpListener;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::State;

fn validate_mount_point(mount_point: &str) -> Result<(), String> {
    let path = std::path::Path::new(mount_point);

    // Must be absolute
    if !path.is_absolute() {
        return Err("Mount point must be an absolute path".to_string());
    }

    // Must not contain .. components
    for component in path.components() {
        if let std::path::Component::ParentDir = component {
            return Err("Mount point must not contain '..' components".to_string());
        }
    }

    // Must be under user's home directory
    if let Some(home) = dirs::home_dir() {
        if !path.starts_with(&home) {
            return Err(format!(
                "Mount point must be under your home directory ({})",
                home.display()
            ));
        }
    }

    Ok(())
}

fn validate_remote(remote: &str) -> Result<(), String> {
    // Remote should match pattern: alphanumeric/hyphens/underscores, optionally ending with ':'
    let name = remote.trim_end_matches(':');
    if name.is_empty() {
        return Err("Remote name cannot be empty".to_string());
    }
    if !name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == ' ') {
        return Err("Remote name contains invalid characters".to_string());
    }
    Ok(())
}

pub struct MountEntry {
    pub remote: String,
    pub mount_point: String,
    pub port: u16,
    pub nfs_server: Child,
}

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

static NFS_SUPPORT_VALIDATED: AtomicBool = AtomicBool::new(false);

pub fn validate_rclone_nfs_support() -> Result<(), String> {
    if NFS_SUPPORT_VALIDATED.load(Ordering::Relaxed) {
        return Ok(());
    }
    let output = Command::new("rclone")
        .args(["serve", "nfs", "--help"])
        .output()
        .map_err(|e| format!("Failed to run rclone: {}", e))?;
    if !output.status.success() {
        return Err("rclone does not support 'serve nfs'. Update to rclone v1.62+.".to_string());
    }
    NFS_SUPPORT_VALIDATED.store(true, Ordering::Relaxed);
    Ok(())
}

pub async fn spawn_nfs_server(remote: &str, port: u16, read_only: bool) -> Result<Child, String> {
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
        args.extend(["--vfs-cache-mode".to_string(), "writes".to_string()]);
    }

    let mut child = Command::new("rclone")
        .args(&args)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start rclone serve nfs: {}", e))?;

    let start = Instant::now();
    let timeout = Duration::from_secs(10);
    while start.elapsed() < timeout {
        // Check if child exited early (startup failure)
        if let Ok(Some(status)) = child.try_wait() {
            let stderr = child.stderr.take()
                .map(|mut s| {
                    let mut buf = String::new();
                    use std::io::Read;
                    let _ = s.read_to_string(&mut buf);
                    buf
                })
                .unwrap_or_default();
            return Err(format!(
                "rclone serve nfs exited with {}: {}",
                status, stderr.trim()
            ));
        }
        if TcpListener::bind(("127.0.0.1", port)).is_err() {
            return Ok(child);
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    let _ = child.kill();
    let _ = child.wait();
    Err(format!(
        "rclone NFS server did not start within 10s on port {}",
        port
    ))
}

fn mount_nfs_share(port: u16, mount_point: &str, remote_name: &str) -> Result<(), String> {
    std::fs::create_dir_all(mount_point)
        .map_err(|e| format!("Failed to create mount point {}: {}", mount_point, e))?;

    let volume_name = remote_name.trim_end_matches(':');
    let output = Command::new("mount_nfs")
        .args([
            "-o",
            &format!(
                "nfsvers=3,tcp,nolocks,noresvport,soft,timeo=50,nosuid,nodev,port={},mountport={},volname={}",
                port, port, volume_name
            ),
            "localhost:/",
            mount_point,
        ])
        .output()
        .map_err(|e| format!("Failed to run mount_nfs: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("mount_nfs failed: {}", stderr.trim()));
    }
    Ok(())
}

fn unmount_nfs_share(mount_point: &str) -> Result<(), String> {
    let mut child = Command::new("umount")
        .arg(mount_point)
        .spawn()
        .map_err(|e| format!("Failed to run umount: {}", e))?;

    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if status.success() {
                    return Ok(());
                }
                return Err(format!("umount failed with exit code: {}", status));
            }
            Ok(None) => {
                if start.elapsed() > Duration::from_secs(5) {
                    let _ = child.kill();
                    let _ = child.wait();
                    // Try force unmount
                    let _ = Command::new("diskutil")
                        .args(["unmount", "force", mount_point])
                        .output();
                    return Err(format!("umount timed out for {}, forced", mount_point));
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            Err(e) => return Err(format!("Failed to check umount status: {}", e)),
        }
    }
}

#[derive(Serialize, Clone)]
pub struct NfsMountInfo {
    pub remote: String,
    pub mount_point: String,
    pub port: u16,
}

#[tauri::command]
pub async fn nfs_mount(
    state: State<'_, NfsMountState>,
    remote: String,
    mount_point: String,
    read_only: bool,
) -> Result<(), String> {
    validate_mount_point(&mount_point)?;
    validate_remote(&remote)?;

    validate_rclone_nfs_support()?;

    {
        let mounts = state.mounts.lock().unwrap();
        if mounts.contains_key(&mount_point) {
            return Err(format!("Mount point {} is already active", mount_point));
        }
    }

    let port = {
        let mounts = state.mounts.lock().unwrap();
        let active_ports: Vec<u16> = mounts.values().map(|m| m.port).collect();
        find_nfs_port(&active_ports)
            .ok_or_else(|| format!("No available port in range {}-{}", NFS_PORT_START, NFS_PORT_END))?
    };

    let child = spawn_nfs_server(&remote, port, read_only).await?;

    let mp = mount_point.clone();
    let rname = remote.clone();
    let mount_result = tokio::task::spawn_blocking(move || mount_nfs_share(port, &mp, &rname))
        .await
        .map_err(|e| format!("Mount task panicked: {}", e))?;

    if let Err(e) = mount_result {
        let mut child = child;
        let _ = child.kill();
        let _ = child.wait();
        return Err(e);
    }

    let entry = MountEntry {
        remote,
        mount_point: mount_point.clone(),
        port,
        nfs_server: child,
    };
    state.mounts.lock().unwrap().insert(mount_point, entry);
    Ok(())
}

#[tauri::command]
pub async fn nfs_unmount(
    state: State<'_, NfsMountState>,
    mount_point: String,
) -> Result<(), String> {
    let entry = state.mounts.lock().unwrap().remove(&mount_point);
    match entry {
        Some(mut entry) => {
            let mp = entry.mount_point.clone();
            let unmount_result = tokio::task::spawn_blocking(move || unmount_nfs_share(&mp))
                .await
                .map_err(|e| format!("Unmount task panicked: {}", e))?;
            let _ = entry.nfs_server.kill();
            let _ = entry.nfs_server.wait();
            unmount_result
        }
        None => Err(format!("No active NFS mount at {}", mount_point)),
    }
}

#[tauri::command]
pub fn nfs_list_mounts(state: State<'_, NfsMountState>) -> Vec<NfsMountInfo> {
    state.mounts.lock().unwrap()
        .values()
        .map(|e| NfsMountInfo {
            remote: e.remote.clone(),
            mount_point: e.mount_point.clone(),
            port: e.port,
        })
        .collect()
}

pub fn cleanup_all_mounts(state: &NfsMountState) {
    let mut mounts = state.mounts.lock().unwrap();
    for (_, mut entry) in mounts.drain() {
        let _ = unmount_nfs_share(&entry.mount_point);
        let _ = entry.nfs_server.kill();
        let _ = entry.nfs_server.wait();
    }
}

pub fn cleanup_stale_mounts(mount_points: &[String]) {
    let output = match Command::new("mount").output() {
        Ok(o) => o,
        Err(_) => return,
    };
    let mount_output = String::from_utf8_lossy(&output.stdout);
    for line in mount_output.lines() {
        if !line.contains("localhost") || !line.contains("nfs") {
            continue;
        }
        for mp in mount_points {
            if line.contains(mp.as_str()) {
                eprintln!("Detected stale NFS mount at {}, cleaning up...", mp);
                let child = Command::new("diskutil")
                    .args(["unmount", mp])
                    .spawn();
                if let Ok(mut child) = child {
                    let start = Instant::now();
                    loop {
                        match child.try_wait() {
                            Ok(Some(_)) => break,
                            Ok(None) if start.elapsed() > Duration::from_secs(5) => {
                                eprintln!("Unmount timed out for {}, force killing", mp);
                                let _ = child.kill();
                                let _ = child.wait();
                                let _ = Command::new("diskutil")
                                    .args(["unmount", "force", mp])
                                    .output();
                                break;
                            }
                            Ok(None) => thread::sleep(Duration::from_millis(100)),
                            Err(_) => break,
                        }
                    }
                }
            }
        }
    }
}

pub fn check_nfs_health(state: &NfsMountState) -> Vec<String> {
    let mut dead_mounts = Vec::new();
    let mut mounts = state.mounts.lock().unwrap();
    let dead_keys: Vec<String> = mounts
        .iter_mut()
        .filter_map(|(key, entry)| {
            match entry.nfs_server.try_wait() {
                Ok(Some(_)) => Some(key.clone()),
                Ok(None) => None,
                Err(_) => Some(key.clone()),
            }
        })
        .collect();
    for key in dead_keys {
        if let Some(entry) = mounts.remove(&key) {
            eprintln!("NFS server died for mount {}", key);
            let _ = unmount_nfs_share(&entry.mount_point);
            dead_mounts.push(entry.mount_point);
        }
    }
    dead_mounts
}
