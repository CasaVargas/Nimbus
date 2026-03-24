import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { listMounts, mountRemote, unmountRemote } from "@/lib/rclone/mount";

export function useActiveMounts() {
  return useQuery({
    queryKey: ["mounts"],
    queryFn: () => listMounts(),
    refetchInterval: 10_000,
  });
}

export function useMountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      fs,
      mountPoint,
      vfsOpt,
    }: {
      fs: string;
      mountPoint: string;
      vfsOpt?: Record<string, unknown>;
    }) => mountRemote(fs, mountPoint, {}, vfsOpt),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mounts"] });
    },
  });
}

export function useUnmountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (mountPoint: string) => unmountRemote(mountPoint),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mounts"] });
    },
  });
}
