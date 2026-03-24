import {
  ArrowRight,
  Ban,
  CheckCircle2,
  Copy,
  FolderSync,
  Loader2,
  Square,
  XCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import type { Transfer } from "@/stores/transfer-store";

const statusIcons: Record<Transfer["status"], React.ReactNode> = {
  active: <Loader2 className="h-4 w-4 animate-spin text-blue-500" />,
  completed: <CheckCircle2 className="h-4 w-4 text-green-500" />,
  failed: <XCircle className="h-4 w-4 text-destructive" />,
  cancelled: <Ban className="h-4 w-4 text-muted-foreground" />,
};

interface TransferItemProps {
  transfer: Transfer;
  onCancel?: (jobId: number) => void;
}

export function TransferItem({ transfer, onCancel }: TransferItemProps) {
  const OperationIcon = transfer.operation === "copy" ? Copy : FolderSync;

  return (
    <div className="flex items-center gap-3 rounded-lg border px-4 py-3">
      {statusIcons[transfer.status]}
      <OperationIcon className="h-4 w-4 text-muted-foreground" />
      <div className="flex min-w-0 flex-1 items-center gap-1.5 text-sm">
        <span className="truncate font-medium">{transfer.srcFs}</span>
        <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" />
        <span className="truncate font-medium">{transfer.dstFs}</span>
      </div>
      {transfer.error && (
        <span className="shrink-0 text-xs text-destructive">
          {transfer.error}
        </span>
      )}
      {transfer.status === "active" && onCancel && (
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
  );
}
