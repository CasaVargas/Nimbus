import { useQuery } from "@tanstack/react-query";
import { listFiles } from "@/lib/rclone/operations";
import type { FileItem } from "@/lib/rclone/types";

export function useFileList(remote: string | undefined, path: string) {
  return useQuery<FileItem[]>({
    queryKey: ["files", remote, path],
    queryFn: () => listFiles(`${remote}:`, path),
    enabled: !!remote,
  });
}
