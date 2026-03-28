import { useEffect, useRef } from "react";
import { fpCleanupStaleDomains, fpSyncState } from "@/lib/tauri/file-provider";
import { getPlatform } from "@/lib/platform";

/**
 * Syncs File Provider shared state when the rclone daemon connects.
 * Writes rclone port and remote names to the App Group container
 * so the File Provider extension can discover the daemon.
 */
export function useFileProviderSync(daemonConnected: boolean, remotes: string[]) {
  const lastSyncRef = useRef<string>("");
  const cleanedUpRef = useRef(false);

  useEffect(() => {
    if (!daemonConnected || getPlatform() !== "macos") return;

    // Only sync when remotes actually change
    const key = remotes.sort().join(",");
    if (key === lastSyncRef.current) return;

    fpSyncState(remotes)
      .then(() => {
        lastSyncRef.current = key;
        console.log("File Provider state synced:", remotes);

        // Clean up stale domains on first sync
        if (!cleanedUpRef.current) {
          cleanedUpRef.current = true;
          fpCleanupStaleDomains(remotes)
            .then((removed) => {
              if (removed.length > 0) {
                console.log("Cleaned up stale File Provider domains:", removed);
              }
            })
            .catch((e) => console.error("Failed to cleanup stale domains:", e));
        }
      })
      .catch((e) => {
        console.error("Failed to sync File Provider state:", e);
      });
  }, [daemonConnected, remotes]);
}
