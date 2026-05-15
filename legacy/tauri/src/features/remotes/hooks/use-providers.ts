import { useQuery } from "@tanstack/react-query";
import { getProviders } from "@/lib/rclone/remotes";
import type { Provider } from "@/lib/rclone/types";

export function useProviders() {
  return useQuery<Provider[]>({
    queryKey: ["providers"],
    queryFn: async () => {
      const res = await getProviders();
      return res.providers;
    },
    staleTime: Infinity,
  });
}
