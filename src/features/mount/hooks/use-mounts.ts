import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listMounts, mountRemote, unmountRemote } from "@/lib/rclone/mount";
import { nfsListMounts, nfsMount, nfsUnmount } from "@/lib/tauri/nfs-mount";
import type { MountBackend } from "@/stores/mount-store";

export function useActiveMounts(backend: MountBackend) {
  return useQuery({
    queryKey: ["mounts", backend],
    queryFn: async () => {
      if (backend === "nfs") {
        const mounts = await nfsListMounts();
        return mounts.map((m) => ({
          Fs: m.remote,
          MountPoint: m.mount_point,
          MountedOn: m.mount_point,
        }));
      }
      return listMounts();
    },
    refetchInterval: 10_000,
  });
}

export function useMountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ fs, mountPoint, vfsOpt, backend }: {
      fs: string; mountPoint: string; vfsOpt?: Record<string, unknown>; backend: MountBackend;
    }) => {
      if (backend === "nfs") {
        return nfsMount(fs, mountPoint, vfsOpt?.readOnly === true);
      }
      return mountRemote(fs, mountPoint, {}, vfsOpt);
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["mounts", variables.backend] });
    },
  });
}

export function useUnmountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ mountPoint, backend }: { mountPoint: string; backend: MountBackend }) => {
      if (backend === "nfs") return nfsUnmount(mountPoint);
      return unmountRemote(mountPoint);
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["mounts", variables.backend] });
    },
  });
}
