import { rclone } from "./client";
import type { ListMountsResponse, MountInfo } from "./types";

export async function mountRemote(
  fs: string,
  mountPoint: string,
  mountOpt?: Record<string, unknown>,
  vfsOpt?: Record<string, unknown>
): Promise<void> {
  await rclone.call("mount/mount", {
    fs,
    mountPoint,
    mountOpt: mountOpt ?? {},
    vfsOpt: vfsOpt ?? {},
  });
}

export async function unmountRemote(mountPoint: string): Promise<void> {
  await rclone.call("mount/unmount", { mountPoint });
}

export async function listMounts(): Promise<MountInfo[]> {
  const res = await rclone.call<ListMountsResponse>("mount/listmounts", {});
  return res.mountPoints ?? [];
}
