import { create } from "zustand";
import { persist } from "zustand/middleware";

export type Theme = "light" | "dark" | "system";

interface AppState {
  theme: Theme;
  sidebarCollapsed: boolean;
  rclonePort: number;
  rcloneBinaryPath: string;
  bandwidthLimit: string;
  concurrentTransfers: number;
  setTheme: (theme: Theme) => void;
  toggleSidebar: () => void;
  setRclonePort: (port: number) => void;
  setRcloneBinaryPath: (path: string) => void;
  setBandwidthLimit: (limit: string) => void;
  setConcurrentTransfers: (count: number) => void;
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      theme: "system",
      sidebarCollapsed: false,
      rclonePort: 5572,
      rcloneBinaryPath: "",
      bandwidthLimit: "",
      concurrentTransfers: 4,
      setTheme: (theme) => set({ theme }),
      toggleSidebar: () =>
        set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),
      setRclonePort: (port) => set({ rclonePort: port }),
      setRcloneBinaryPath: (path) => set({ rcloneBinaryPath: path }),
      setBandwidthLimit: (limit) => set({ bandwidthLimit: limit }),
      setConcurrentTransfers: (count) => set({ concurrentTransfers: count }),
    }),
    { name: "streamcloned-app" },
  ),
);
