import { invoke } from "@tauri-apps/api/core";

export async function startRclone(): Promise<number> {
  return invoke<number>("start_rclone");
}

export async function stopRclone(): Promise<void> {
  return invoke<void>("stop_rclone");
}

export async function getRclonePort(): Promise<number> {
  return invoke<number>("get_rclone_port");
}

export async function isRcloneRunning(): Promise<boolean> {
  return invoke<boolean>("is_rclone_running");
}
