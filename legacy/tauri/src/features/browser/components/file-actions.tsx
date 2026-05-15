import { Download, ExternalLink } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";

interface FileActionsProps {
  item: FileItem;
  onOpen: (item: FileItem) => void;
  onDownload: (item: FileItem) => void;
}

export function FileActions({ item, onOpen, onDownload }: FileActionsProps) {
  return (
    <div
      className="flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover/row:opacity-100"
      onClick={(e) => e.stopPropagation()}
      onDoubleClick={(e) => e.stopPropagation()}
    >
      <button
        type="button"
        className="rounded p-1 hover:bg-accent"
        onClick={() => onOpen(item)}
        title={item.IsDir ? "Open folder" : "Open with system app"}
      >
        <ExternalLink className="size-3.5 text-muted-foreground" />
      </button>
      {!item.IsDir && (
        <button
          type="button"
          className="rounded p-1 hover:bg-accent"
          onClick={() => onDownload(item)}
          title="Download"
        >
          <Download className="size-3.5 text-muted-foreground" />
        </button>
      )}
    </div>
  );
}
