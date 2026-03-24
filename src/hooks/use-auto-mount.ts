import { useEffect, useRef } from "react";
import { getPlatform } from "@/lib/platform";
import { nfsMount } from "@/lib/tauri/nfs-mount";
import { mountRemote } from "@/lib/rclone/mount";
import { useMountStore } from "@/stores/mount-store";

export function useAutoMount(daemonConnected: boolean) {
  const hasRun = useRef(false);
  const configs = useMountStore((s) => s.configs);

  useEffect(() => {
    if (!daemonConnected || hasRun.current) return;
    hasRun.current = true;
    const autoConfigs = configs.filter((c) => c.autoMount);
    if (autoConfigs.length === 0) return;
    const plat = getPlatform();
    (async () => {
      for (const config of autoConfigs) {
        try {
          if (config.backend === "nfs" || (plat === "macos" && !config.backend)) {
            await nfsMount(config.remote, config.mountPoint, config.vfsMode === "read-only");
          } else {
            await mountRemote(config.remote, config.mountPoint, {},
              config.vfsMode === "read-only" ? { readOnly: true } : undefined);
          }
        } catch (e) {
          console.error(`Failed to auto-mount ${config.remote}:`, e);
        }
      }
    })();
  }, [daemonConnected, configs]);
}
