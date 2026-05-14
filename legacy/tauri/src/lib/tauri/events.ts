import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export function onDaemonStatusChange(
  callback: (running: boolean) => void,
): Promise<UnlistenFn> {
  return listen<boolean>("daemon-status", (event) => {
    callback(event.payload);
  });
}
