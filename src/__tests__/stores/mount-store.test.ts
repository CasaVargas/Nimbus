import { beforeEach, describe, expect, it } from "vitest";
import { useMountStore } from "../../stores/mount-store";

describe("mountStore", () => {
  beforeEach(() => {
    useMountStore.setState({ configs: [] });
  });

  it("adds a mount config", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/mnt/gdrive",
      vfsMode: "read-only",
      autoMount: false,
    });

    const configs = useMountStore.getState().configs;
    expect(configs).toHaveLength(1);
    expect(configs[0].remote).toBe("gdrive:");
    expect(configs[0].mountPoint).toBe("/mnt/gdrive");
    expect(configs[0].vfsMode).toBe("read-only");
    expect(configs[0].autoMount).toBe(false);
  });

  it("removes a mount config by mount point", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/mnt/gdrive",
      vfsMode: "read-only",
      autoMount: false,
    });
    useMountStore.getState().addConfig({
      remote: "s3:",
      mountPoint: "/mnt/s3",
      vfsMode: "read-write",
      autoMount: true,
    });

    useMountStore.getState().removeConfig("/mnt/gdrive");

    const configs = useMountStore.getState().configs;
    expect(configs).toHaveLength(1);
    expect(configs[0].remote).toBe("s3:");
  });

  it("toggles auto-mount for a config", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/mnt/gdrive",
      vfsMode: "read-only",
      autoMount: false,
    });

    useMountStore.getState().toggleAutoMount("/mnt/gdrive");
    expect(useMountStore.getState().configs[0].autoMount).toBe(true);

    useMountStore.getState().toggleAutoMount("/mnt/gdrive");
    expect(useMountStore.getState().configs[0].autoMount).toBe(false);
  });
});
