import { useMutation } from "@tanstack/react-query";
import { copy, sync } from "@/lib/rclone/sync";
import { useTransferStore } from "@/stores/transfer-store";

interface SyncParams {
  operation: "copy" | "sync";
  srcFs: string;
  dstFs: string;
  dryRun?: boolean;
}

export function useCopySync() {
  const addTransfer = useTransferStore((s) => s.addTransfer);

  return useMutation({
    mutationFn: async ({ operation, srcFs, dstFs, dryRun }: SyncParams) => {
      const opts = {
        srcFs,
        dstFs,
        _async: true,
        ...(dryRun ? { _config: { DryRun: true } } : {}),
      };

      const fn = operation === "copy" ? copy : sync;
      const result = await fn(opts);

      if (!dryRun) {
        addTransfer({
          jobId: result.jobid,
          operation,
          srcFs,
          dstFs,
        });
      }

      return result;
    },
  });
}
