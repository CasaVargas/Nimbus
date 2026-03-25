use serde::Serialize;
use std::process::Command;
use tauri::State;

use super::rclone::RcloneState;

const APP_GROUP_ID: &str = "group.com.streamcloned.app";

#[derive(Serialize, Clone)]
pub struct FileProviderDomainInfo {
    pub identifier: String,
    pub display_name: String,
    pub enabled: bool,
}

/// Write shared state JSON to the App Group container so the File Provider extension
/// can discover the rclone RC port and configured remotes.
fn write_shared_state(rclone_port: u16, remotes: &[String]) -> Result<(), String> {
    let container_path = get_app_group_container()?;
    let state_path = format!("{}/fileprovider-state.json", container_path);

    let state = serde_json::json!({
        "rclonePort": rclone_port,
        "remotes": remotes,
        "updatedAt": chrono::Utc::now().to_rfc3339(),
    });

    std::fs::write(&state_path, serde_json::to_string_pretty(&state).unwrap())
        .map_err(|e| format!("Failed to write shared state: {}", e))?;

    Ok(())
}

fn get_app_group_container() -> Result<String, String> {
    // On macOS, App Group containers are at:
    // ~/Library/Group Containers/<group-id>/
    let home = dirs::home_dir().ok_or("Could not determine home directory")?;
    let container = home
        .join("Library")
        .join("Group Containers")
        .join(APP_GROUP_ID);

    std::fs::create_dir_all(&container)
        .map_err(|e| format!("Failed to create App Group container: {}", e))?;

    Ok(container.to_string_lossy().to_string())
}

#[tauri::command]
pub async fn fp_sync_state(
    rclone_state: State<'_, RcloneState>,
    remotes: Vec<String>,
) -> Result<(), String> {
    let port = *rclone_state.port.lock().unwrap();
    write_shared_state(port, &remotes)
}

#[tauri::command]
pub async fn fp_add_domain(
    identifier: String,
    display_name: String,
) -> Result<(), String> {
    // Use NSFileProviderManager via swift CLI helper
    // For now, this is a placeholder — domain management requires calling
    // Apple's FileProvider framework from Swift, which we'll do via a small
    // Swift CLI tool built alongside the extension
    log::info!("File Provider domain add requested: {} ({})", display_name, identifier);
    Ok(())
}

#[tauri::command]
pub async fn fp_remove_domain(
    identifier: String,
) -> Result<(), String> {
    log::info!("File Provider domain remove requested: {}", identifier);
    Ok(())
}

#[tauri::command]
pub fn fp_is_supported() -> bool {
    // File Provider is only supported on macOS 12+
    #[cfg(target_os = "macos")]
    {
        let output = Command::new("sw_vers")
            .args(["-productVersion"])
            .output();
        if let Ok(output) = output {
            let version = String::from_utf8_lossy(&output.stdout);
            let major: u32 = version.trim().split('.').next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            return major >= 12;
        }
        false
    }
    #[cfg(not(target_os = "macos"))]
    {
        false
    }
}
