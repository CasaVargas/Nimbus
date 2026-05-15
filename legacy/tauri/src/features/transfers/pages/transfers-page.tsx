import { ArrowDownUp } from "lucide-react";
import { useMemo } from "react";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { useTransferStore } from "@/stores/transfer-store";
import { TransferItem } from "../components/transfer-item";
import {
  useActiveTransfers,
  useCancelTransfer,
  usePerJobStats,
  useTransferStats,
} from "../hooks/use-transfers";

function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec < 1024) return `${bytesPerSec} B/s`;
  if (bytesPerSec < 1024 * 1024)
    return `${(bytesPerSec / 1024).toFixed(1)} KB/s`;
  if (bytesPerSec < 1024 * 1024 * 1024)
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} MB/s`;
  return `${(bytesPerSec / (1024 * 1024 * 1024)).toFixed(2)} GB/s`;
}

export default function TransfersPage() {
  const { transfers, activeTransfers } = useActiveTransfers();
  const { data: stats } = useTransferStats();
  const cancelTransfer = useCancelTransfer();
  const clearCompleted = useTransferStore((s) => s.clearCompleted);
  const completedTransfers = transfers.filter((t) => t.status !== "active");
  const hasCompleted = completedTransfers.length > 0;

  const activeJobIds = useMemo(
    () => activeTransfers.map((t) => t.jobId),
    [activeTransfers],
  );
  const perJobStats = usePerJobStats(activeJobIds);

  const speedDesc =
    activeTransfers.length > 0 && stats?.speed
      ? `${activeTransfers.length} active \u00b7 ${formatSpeed(stats.speed)}`
      : "Monitor active file transfers";

  return (
    <div>
      <PageHeader
        title="Transfers"
        description={speedDesc}
        actions={
          hasCompleted ? (
            <Button variant="outline" size="sm" onClick={clearCompleted}>
              Clear Completed
            </Button>
          ) : undefined
        }
      />
      <div className="space-y-6 p-6">
        {transfers.length === 0 && (
          <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
            <ArrowDownUp className="h-10 w-10 text-muted-foreground/50" />
            <div>
              <p className="font-medium text-muted-foreground">
                No transfers yet
              </p>
              <p className="text-sm text-muted-foreground/70">
                Start a copy or sync to see transfers here
              </p>
            </div>
          </div>
        )}

        {activeTransfers.length > 0 && (
          <section className="space-y-2">
            <h2 className="text-sm font-medium text-muted-foreground">
              Active
            </h2>
            <div className="space-y-2">
              {activeTransfers.map((t) => (
                <TransferItem
                  key={t.jobId}
                  transfer={t}
                  stats={perJobStats.get(t.jobId)}
                  onCancel={cancelTransfer}
                />
              ))}
            </div>
          </section>
        )}

        {hasCompleted && (
          <section className="space-y-2">
            <h2 className="text-sm font-medium text-muted-foreground">
              Completed
            </h2>
            <div className="space-y-2">
              {completedTransfers.map((t) => (
                <TransferItem key={t.jobId} transfer={t} />
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
