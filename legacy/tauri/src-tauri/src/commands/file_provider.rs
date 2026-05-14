use serde::Serialize;
use std::path::PathBuf;
use std::process::Command;
use tauri::State;

use super::rclone::RcloneState;

const APP_GROUP_ID: &str = "group.app.casavargas.nimbus";

#[derive(Serialize, Clone)]
pub struct FileProviderDomainInfo {
    pub identifier: String,
    pub display_name: String,
}

/// Get the path to the fp-domain-manager CLI binary
fn domain_manager_path() -> Result<PathBuf, String> {
    // In dev: look in target/extension/
    let dev_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("target")
        .join("extension")
        .join("fp-domain-manager");
    if dev_path.exists() {
        return Ok(dev_path);
    }

    // In production: look relative to the current executable
    if let Ok(exe) = std::env::current_exe() {
        let prod_path = exe.parent()
            .map(|p| p.join("fp-domain-manager"));
        if let Some(p) = prod_path {
            if p.exists() {
                return Ok(p);
            }
        }
    }

    Err("fp-domain-manager binary not found. Run build-extension.sh first.".to_string())
}

fn run_domain_manager(args: &[&str]) -> Result<String, String> {
    let binary = domain_manager_path()?;
    let output = Command::new(&binary)
        .args(args)
        .output()
        .map_err(|e| format!("Failed to run fp-domain-manager: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        return Err(format!("fp-domain-manager failed: {}", stderr.trim()));
    }

    Ok(stdout)
}

fn get_app_group_container() -> Result<String, String> {
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
    let container_path = get_app_group_container()?;
    let state_path = format!("{}/fileprovider-state.json", container_path);

    let state = serde_json::json!({
        "rclonePort": port,
        "remotes": remotes,
        "updatedAt": chrono::Utc::now().to_rfc3339(),
    });

    std::fs::write(&state_path, serde_json::to_string_pretty(&state).unwrap())
        .map_err(|e| format!("Failed to write shared state: {}", e))?;

    Ok(())
}

#[tauri::command]
pub async fn fp_add_domain(
    identifier: String,
    display_name: String,
) -> Result<(), String> {
    // Validate identifier
    if identifier.is_empty() {
        return Err("Domain identifier cannot be empty".to_string());
    }
    if !identifier.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return Err("Domain identifier contains invalid characters".to_string());
    }

    run_domain_manager(&["add", &identifier, &display_name])?;
    Ok(())
}

#[tauri::command]
pub async fn fp_remove_domain(
    identifier: String,
) -> Result<(), String> {
    run_domain_manager(&["remove", &identifier])?;
    Ok(())
}

#[tauri::command]
pub async fn fp_list_domains() -> Result<Vec<FileProviderDomainInfo>, String> {
    let output = run_domain_manager(&["list"])?;
    let mut domains = Vec::new();

    for line in output.lines() {
        if line.starts_with("No File Provider") || line.is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.splitn(2, '\t').collect();
        if parts.len() == 2 {
            domains.push(FileProviderDomainInfo {
                identifier: parts[0].to_string(),
                display_name: parts[1].to_string(),
            });
        }
    }

    Ok(domains)
}

#[tauri::command]
pub async fn fp_cleanup_stale_domains(
    active_remotes: Vec<String>,
) -> Result<Vec<String>, String> {
    let domains = fp_list_domains().await?;
    let mut removed = Vec::new();

    for domain in &domains {
        if !active_remotes.contains(&domain.identifier) {
            match run_domain_manager(&["remove", &domain.identifier]) {
                Ok(_) => {
                    removed.push(domain.identifier.clone());
                    log::info!("Cleaned up stale domain: {}", domain.identifier);
                }
                Err(e) => {
                    log::warn!("Failed to remove stale domain {}: {}", domain.identifier, e);
                }
            }
        }
    }

    Ok(removed)
}

#[tauri::command]
pub fn fp_is_supported() -> bool {
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
