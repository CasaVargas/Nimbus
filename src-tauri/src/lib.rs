mod commands;
mod tray;
use commands::nfs_mount::NfsMountState;
use commands::rclone::RcloneState;
use tauri::Manager;

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

            // Clean up stale NFS mounts from a previous crash
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

            // Spawn background health monitor for NFS servers
            let app_handle = app.handle().clone();
            std::thread::spawn(move || loop {
                std::thread::sleep(std::time::Duration::from_secs(10));
                let nfs_state: tauri::State<NfsMountState> = app_handle.state();
                let dead = commands::nfs_mount::check_nfs_health(nfs_state.inner());
                for mp in &dead {
                    eprintln!("NFS mount at {} was cleaned up due to server crash", mp);
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
