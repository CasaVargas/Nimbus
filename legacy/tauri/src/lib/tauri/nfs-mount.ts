import { invoke } from "@tauri-apps/api/core";

export interface NfsMountInfo {
  remote: string;
  mount_point: string;
  port: number;
}

export async function nfsMount(remote: string, mountPoint: string, readOnly: boolean): Promise<void> {
  return invoke<void>("nfs_mount", { remote, mountPoint, readOnly });
}

export async function nfsUnmount(mountPoint: string): Promise<void> {
  return invoke<void>("nfs_unmount", { mountPoint });
}

export async function nfsListMounts(): Promise<NfsMountInfo[]> {
  return invoke<NfsMountInfo[]>("nfs_list_mounts");
}
