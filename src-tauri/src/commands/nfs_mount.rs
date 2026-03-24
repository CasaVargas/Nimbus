use std::collections::HashMap;
use std::net::TcpListener;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

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
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to start rclone serve nfs: {}", e))?;

    let start = Instant::now();
    let timeout = Duration::from_secs(10);
    while start.elapsed() < timeout {
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
