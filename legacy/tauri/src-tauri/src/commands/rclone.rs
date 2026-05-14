use std::net::TcpListener;
use std::process::{Child, Command};
use std::sync::Mutex;
use tauri::State;

pub struct RcloneState {
    pub port: Mutex<u16>,
    pub running: Mutex<bool>,
    pub child: Mutex<Option<Child>>,
}

impl Default for RcloneState {
    fn default() -> Self {
        Self {
            port: Mutex::new(5572),
            running: Mutex::new(false),
            child: Mutex::new(None),
        }
    }
}

fn find_available_port(start: u16) -> Option<u16> {
    for port in start..=start + 8 {
        if TcpListener::bind(("127.0.0.1", port)).is_ok() {
            return Some(port);
        }
    }
    None
}

#[tauri::command]
pub async fn start_rclone(
    state: State<'_, RcloneState>,
) -> Result<u16, String> {
    // If already running, return the current port
    if *state.running.lock().unwrap() {
        return Ok(*state.port.lock().unwrap());
    }

    let port = find_available_port(5572).ok_or("No available port in range 5572-5580")?;

    let child = Command::new("rclone")
        .args([
            "rcd",
            "--rc-no-auth",
            "--rc-addr",
            &format!("127.0.0.1:{}", port),
            "--rc-allow-origin=*",
        ])
        .spawn()
        .map_err(|e| format!("Failed to start rclone: {}", e))?;

    *state.port.lock().unwrap() = port;
    *state.running.lock().unwrap() = true;
    *state.child.lock().unwrap() = Some(child);

    Ok(port)
}

#[tauri::command]
pub fn stop_rclone(state: State<'_, RcloneState>) -> Result<(), String> {
    if let Some(mut child) = state.child.lock().unwrap().take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *state.running.lock().unwrap() = false;
    Ok(())
}

#[tauri::command]
pub fn get_rclone_port(state: State<'_, RcloneState>) -> u16 {
    *state.port.lock().unwrap()
}

#[tauri::command]
pub fn is_rclone_running(state: State<'_, RcloneState>) -> bool {
    *state.running.lock().unwrap()
}
