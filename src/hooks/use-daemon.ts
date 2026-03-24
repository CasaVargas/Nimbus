import { useEffect, useState, useCallback } from "react";
import { startRclone } from "../lib/tauri/rclone";
import { rclone } from "../lib/rclone/client";
import { useAppStore } from "../stores/app-store";

type DaemonStatus = "connecting" | "connected" | "error";

export function useDaemon() {
  const [status, setStatus] = useState<DaemonStatus>("connecting");
  const [error, setError] = useState<string | null>(null);
  const setRclonePort = useAppStore((s) => s.setRclonePort);
  const [retryCount, setRetryCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function connect() {
      setStatus("connecting");
      setError(null);
      try {
        let port = 5572;
        try {
          port = await startRclone();
        } catch {
          // Tauri IPC not available (dev browser) — try default port
        }
        if (cancelled) return;
        setRclonePort(port);
        rclone.setBaseUrl(`http://localhost:${port}`);

        let attempts = 0;
        while (attempts < 30) {
          if (cancelled) return;
          const alive = await rclone.healthCheck();
          if (alive) {
            setStatus("connected");
            return;
          }
          attempts++;
          await new Promise((r) => setTimeout(r, 500));
        }
        throw new Error("Rclone daemon did not respond after 15 seconds");
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Unknown error");
        setStatus("error");
      }
    }
    connect();
    return () => {
      cancelled = true;
    };
  }, [setRclonePort, retryCount]);

  const retry = useCallback(() => setRetryCount((c) => c + 1), []);
  return { status, error, retry };
}
