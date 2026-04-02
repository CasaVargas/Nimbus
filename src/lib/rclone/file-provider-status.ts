import { invoke } from "@tauri-apps/api/core";

export type CloudStatus = "local" | "cloud" | "downloading" | "unknown";

export async function getCloudStatus(
  remoteName: string,
  path: string,
): Promise<CloudStatus> {
  try {
    return await invoke<CloudStatus>("get_cloud_status", { remoteName, path });
  } catch {
    return "unknown";
  }
}

export async function evictFile(
  remoteName: string,
  path: string,
): Promise<void> {
  await invoke("evict_file", { remoteName, path });
}

export async function materializeFile(
  remoteName: string,
  path: string,
): Promise<void> {
  await invoke("materialize_file", { remoteName, path });
}
