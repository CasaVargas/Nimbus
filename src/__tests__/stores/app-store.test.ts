import { describe, it, expect, beforeEach } from "vitest";
import { useAppStore } from "../../stores/app-store";

describe("appStore", () => {
  beforeEach(() => {
    useAppStore.setState({
      theme: "system",
      sidebarCollapsed: false,
      rclonePort: 5572,
      rcloneBinaryPath: "",
      bandwidthLimit: "",
      concurrentTransfers: 4,
    });
  });

  it("has correct default values", () => {
    const state = useAppStore.getState();
    expect(state.theme).toBe("system");
    expect(state.sidebarCollapsed).toBe(false);
    expect(state.rclonePort).toBe(5572);
    expect(state.concurrentTransfers).toBe(4);
  });

  it("sets theme", () => {
    useAppStore.getState().setTheme("dark");
    expect(useAppStore.getState().theme).toBe("dark");
  });

  it("toggles sidebar", () => {
    useAppStore.getState().toggleSidebar();
    expect(useAppStore.getState().sidebarCollapsed).toBe(true);
    useAppStore.getState().toggleSidebar();
    expect(useAppStore.getState().sidebarCollapsed).toBe(false);
  });

  it("sets rclone port", () => {
    useAppStore.getState().setRclonePort(5573);
    expect(useAppStore.getState().rclonePort).toBe(5573);
  });
});
