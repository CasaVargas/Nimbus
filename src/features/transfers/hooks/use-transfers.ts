import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { jobStatus, stopJob } from "@/lib/rclone/jobs";
import { getStats } from "@/lib/rclone/stats";
import { useTransferStore } from "@/stores/transfer-store";

export function useActiveTransfers() {
  const transfers = useTransferStore((s) => s.transfers);
  const completeTransfer = useTransferStore((s) => s.completeTransfer);
  const activeTransfers = transfers.filter((t) => t.status === "active");

  const { data: jobStatuses } = useQuery({
    queryKey: ["job-statuses", activeTransfers.map((t) => t.jobId)],
    queryFn: async () => {
      const results = await Promise.allSettled(
        activeTransfers.map((t) => jobStatus(t.jobId)),
      );
      return results.map((r, i) => ({
        jobId: activeTransfers[i].jobId,
        result: r.status === "fulfilled" ? r.value : null,
        error: r.status === "rejected" ? String(r.reason) : null,
      }));
    },
    enabled: activeTransfers.length > 0,
    refetchInterval: 2000,
  });

  useEffect(() => {
    if (!jobStatuses) return;
    for (const js of jobStatuses) {
      if (js.result?.finished) {
        completeTransfer(
          js.jobId,
          js.result.success,
          js.result.error || undefined,
        );
      } else if (js.error) {
        completeTransfer(js.jobId, false, js.error);
      }
    }
  }, [jobStatuses, completeTransfer]);

  return { transfers, activeTransfers };
}

export function useTransferStats() {
  const transfers = useTransferStore((s) => s.transfers);
  const hasActive = transfers.some((t) => t.status === "active");

  return useQuery({
    queryKey: ["transfer-stats"],
    queryFn: () => getStats(),
    enabled: hasActive,
    refetchInterval: 2000,
  });
}

export function useCancelTransfer() {
  const cancelTransfer = useTransferStore((s) => s.cancelTransfer);

  return async (jobId: number) => {
    await stopJob(jobId);
    cancelTransfer(jobId);
  };
}
