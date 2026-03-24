import { useMutation, useQueryClient } from "@tanstack/react-query";
import * as operations from "@/lib/rclone/operations";

export function useCreateFolder(remote: string, path: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (folderName: string) => {
      const fullPath = path ? `${path}/${folderName}` : folderName;
      return operations.mkdir(`${remote}:`, fullPath);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, path] });
    },
  });
}

export function useDeleteItems(remote: string, path: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (items: { name: string; isDir: boolean }[]) => {
      return Promise.all(
        items.map((item) => {
          const fullPath = path ? `${path}/${item.name}` : item.name;
          return item.isDir
            ? operations.purge(`${remote}:`, fullPath)
            : operations.deleteFile(`${remote}:`, fullPath);
        }),
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, path] });
    },
  });
}

export function useUploadFile(remote: string, path: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (localPath: string) => {
      const fileName = localPath.split("/").pop() ?? localPath.split("\\").pop() ?? "file";
      const remotePath = path ? `${path}/${fileName}` : fileName;
      return operations.copyFile("/", localPath, `${remote}:`, remotePath);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, path] });
    },
  });
}

export function useDownloadFile(remote: string) {
  return useMutation({
    mutationFn: ({
      remotePath,
      localPath,
    }: {
      remotePath: string;
      localPath: string;
    }) => {
      const fileName = remotePath.split("/").pop() ?? "file";
      return operations.copyFile(
        `${remote}:`,
        remotePath,
        "/",
        `${localPath}/${fileName}`,
      );
    },
  });
}
