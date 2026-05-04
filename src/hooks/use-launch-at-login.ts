import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
import { useCallback, useEffect, useState } from "react";

interface LaunchAtLoginState {
  enabled: boolean;
  loading: boolean;
  error: string | null;
  toggle: () => Promise<void>;
  refresh: () => Promise<void>;
}

export function useLaunchAtLogin(): LaunchAtLoginState {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const value = await isEnabled();
      setEnabled(value);
      setError(null);
    } catch (err) {
      setError(formatError(err));
    } finally {
      setLoading(false);
    }
  }, []);

  const toggle = useCallback(async () => {
    setLoading(true);
    try {
      if (enabled) {
        await disable();
        setEnabled(false);
      } else {
        await enable();
        setEnabled(true);
      }
      setError(null);
    } catch (err) {
      setError(formatError(err));
      // Re-sync to whatever the OS actually has.
      await refresh();
    } finally {
      setLoading(false);
    }
  }, [enabled, refresh]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { enabled, loading, error, toggle, refresh };
}

function formatError(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err);
  // The plugin's failure modes on macOS are dominated by "app not in
  // /Applications". Append a hint rather than try to pattern-match the
  // underlying error string, which varies across macOS versions.
  return `${message} (If this fails repeatedly, ensure Nimbus is in your Applications folder.)`;
}
