import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { configDump, deleteRemote, listRemotes } from "@/lib/rclone/remotes";

export interface RemoteEntry {
  name: string;
  type: string;
  config: Record<string, string>;
}

export function useRemotes() {
  return useQuery<RemoteEntry[]>({
    queryKey: ["remotes"],
    queryFn: async () => {
      const [names, dump] = await Promise.all([listRemotes(), configDump()]);
      return names.map((name) => ({
        name,
        type: dump[name]?.type ?? "unknown",
        config: dump[name] ?? {},
      }));
    },
  });
}

export function useDeleteRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => deleteRemote(name),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["remotes"] });
    },
  });
}
