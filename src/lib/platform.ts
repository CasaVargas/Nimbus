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
    cachedPlatform = "unknown";
  }
  return cachedPlatform;
}

export function getDefaultMountBackend(): "nfs" | "fuse" {
  return getPlatform() === "macos" ? "nfs" : "fuse";
}
