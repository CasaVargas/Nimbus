import {
  ArrowRight,
  Ban,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Copy,
  FolderSync,
  Loader2,
  Square,
  XCircle,
} from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { StatsResponse } from "@/lib/rclone/types";
import type { Transfer } from "@/stores/transfer-store";

const statusIcons: Record<Transfer["status"], React.ReactNode> = {
  active: <Loader2 className="h-4 w-4 animate-spin text-blue-500" />,
  completed: <CheckCircle2 className="h-4 w-4 text-green-500" />,
  failed: <XCircle className="h-4 w-4 text-destructive" />,
  cancelled: <Ban className="h-4 w-4 text-muted-foreground" />,
};

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const size = bytes / 1024 ** i;
  return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec <= 0) return "";
  return `${formatBytes(bytesPerSec)}/s`;
}

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) {
    const m = Math.floor(seconds / 60);
    const s = Math.round(seconds % 60);
    return `${m}m ${s}s`;
  }
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m}m`;
}

function formatEta(seconds: number): string {
  if (seconds <= 0) return "";
  return `ETA ${formatDuration(seconds)}`;
}

function ProgressBar({ percent }: { percent: number }) {
  return (
    <div className="h-1.5 w-full rounded-full bg-muted">
      <div
        className="h-full rounded-full bg-primary transition-all duration-300"
        style={{ width: `${Math.min(100, Math.max(0, percent))}%` }}
      />
    </div>
  );
}

interface TransferItemProps {
  transfer: Transfer;
  stats?: StatsResponse;
  onCancel?: (jobId: number) => void;
}

export function TransferItem({ transfer, stats, onCancel }: TransferItemProps) {
  const [expanded, setExpanded] = useState(transfer.status === "active");
  const OperationIcon = transfer.operation === "copy" ? Copy : FolderSync;
  const isActive = transfer.status === "active";

  const percent =
    stats && stats.totalBytes > 0
      ? (stats.bytes / stats.totalBytes) * 100
      : 0;

  const elapsed = stats?.elapsedTime ?? 0;
  const transferring = stats?.transferring ?? [];

  // Summary line for completed/failed
  const completedSummary = !isActive && transfer.completedAt
    ? (() => {
        const start = new Date(transfer.startedAt).getTime();
        const end = new Date(transfer.completedAt).getTime();
        const dur = (end - start) / 1000;
        return formatDuration(dur);
      })()
    : null;

  return (
    <div className="rounded-lg border">
      {/* Header row */}
      <div className="flex items-center gap-3 px-4 py-3">
        {statusIcons[transfer.status]}
        <OperationIcon className="h-4 w-4 text-muted-foreground" />
        <div className="flex min-w-0 flex-1 items-center gap-1.5 text-sm">
          <span className="truncate font-medium">{transfer.srcFs}</span>
          <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" />
          <span className="truncate font-medium">{transfer.dstFs}</span>
        </div>

        {isActive && stats && (
          <span className="shrink-0 text-xs text-muted-foreground">
            {formatSpeed(stats.speed)}
          </span>
        )}

        {transfer.error && (
          <span className="shrink-0 text-xs text-destructive">
            {transfer.error}
          </span>
        )}

        {isActive && transferring.length > 0 && (
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0"
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? (
              <ChevronDown className="h-3.5 w-3.5" />
            ) : (
              <ChevronRight className="h-3.5 w-3.5" />
            )}
          </Button>
        )}

        {isActive && onCancel && (
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0"
            onClick={() => onCancel(transfer.jobId)}
          >
            <Square className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>

      {/* Overall progress bar for active transfers */}
      {isActive && stats && stats.totalBytes > 0 && (
        <div className="space-y-1 px-4 pb-2">
          <ProgressBar percent={percent} />
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>
              {Math.round(percent)}% · {formatBytes(stats.bytes)} /{" "}
              {formatBytes(stats.totalBytes)}
            </span>
            {stats.totalTransfers > 0 && (
              <span>
                · {stats.transfers}/{stats.totalTransfers} files
              </span>
            )}
            {elapsed > 0 && <span>· {formatDuration(elapsed)}</span>}
            {transferring.length > 0 && transferring[0].eta > 0 && (
              <span>· {formatEta(transferring[0].eta)}</span>
            )}
          </div>
        </div>
      )}

      {/* Completed summary */}
      {!isActive && completedSummary && (
        <div className="px-4 pb-3 text-xs text-muted-foreground">
          {stats ? formatBytes(stats.bytes) : ""}{" "}
          {stats && stats.transfers > 0 ? `· ${stats.transfers} files · ` : "· "}
          {completedSummary}
        </div>
      )}

      {/* Per-file progress list */}
      {isActive && expanded && transferring.length > 0 && (
        <div className="border-t px-4 py-2 space-y-1.5">
          {transferring.map((file) => (
            <div key={file.name} className="space-y-0.5">
              <div className="flex items-center gap-2 text-xs">
                <span className="min-w-0 flex-1 truncate text-muted-foreground">
                  {file.name.split("/").pop() ?? file.name}
                </span>
                <span className="shrink-0 text-muted-foreground/70">
                  {Math.round(file.percentage)}%
                </span>
                {file.speed > 0 && (
                  <span className="shrink-0 text-muted-foreground/70">
                    {formatSpeed(file.speed)}
                  </span>
                )}
                {file.eta > 0 && (
                  <span className="shrink-0 text-muted-foreground/70">
                    {formatEta(file.eta)}
                  </span>
                )}
              </div>
              <ProgressBar percent={file.percentage} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
