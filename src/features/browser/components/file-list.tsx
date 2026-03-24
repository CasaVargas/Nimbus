import { Folder, File, ChevronUp, ChevronDown } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";
import { cn } from "@/lib/utils";

export type SortField = "name" | "size" | "modified";
export type SortDir = "asc" | "desc";

interface FileListProps {
  items: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
  sortBy: SortField;
  sortDir: SortDir;
  onSort: (field: SortField) => void;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "--";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const size = bytes / 1024 ** i;
  return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function formatDate(isoString: string): string {
  try {
    return new Date(isoString).toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "--";
  }
}

function SortIcon({
  field,
  sortBy,
  sortDir,
}: {
  field: SortField;
  sortBy: SortField;
  sortDir: SortDir;
}) {
  if (field !== sortBy) return null;
  return sortDir === "asc" ? (
    <ChevronUp className="size-3.5" />
  ) : (
    <ChevronDown className="size-3.5" />
  );
}

export function FileList({
  items,
  selected,
  onSelect,
  onOpen,
  sortBy,
  sortDir,
  onSort,
}: FileListProps) {
  return (
    <div className="rounded-lg border">
      {/* Header */}
      <div
        className="grid items-center gap-2 border-b bg-muted/50 px-3 py-1.5 text-xs font-medium text-muted-foreground"
        style={{ gridTemplateColumns: "1fr 100px 180px" }}
      >
        <button
          type="button"
          className="flex items-center gap-1 text-left hover:text-foreground"
          onClick={() => onSort("name")}
        >
          Name <SortIcon field="name" sortBy={sortBy} sortDir={sortDir} />
        </button>
        <button
          type="button"
          className="flex items-center gap-1 text-left hover:text-foreground"
          onClick={() => onSort("size")}
        >
          Size <SortIcon field="size" sortBy={sortBy} sortDir={sortDir} />
        </button>
        <button
          type="button"
          className="flex items-center gap-1 text-left hover:text-foreground"
          onClick={() => onSort("modified")}
        >
          Modified{" "}
          <SortIcon field="modified" sortBy={sortBy} sortDir={sortDir} />
        </button>
      </div>

      {/* Rows */}
      {items.map((item) => (
        <div
          key={item.Name}
          className={cn(
            "grid cursor-pointer items-center gap-2 border-b px-3 py-1.5 text-sm last:border-b-0 hover:bg-muted/50",
            selected.has(item.Name) && "bg-primary/10",
          )}
          style={{ gridTemplateColumns: "1fr 100px 180px" }}
          onClick={(e) => onSelect(item.Name, e)}
          onDoubleClick={() => onOpen(item)}
        >
          <div className="flex items-center gap-2 truncate">
            {item.IsDir ? (
              <Folder className="size-4 shrink-0 text-blue-500" />
            ) : (
              <File className="size-4 shrink-0 text-muted-foreground" />
            )}
            <span className="truncate">{item.Name}</span>
          </div>
          <span className="text-muted-foreground">
            {item.IsDir ? "--" : formatSize(item.Size)}
          </span>
          <span className="text-muted-foreground">
            {formatDate(item.ModTime)}
          </span>
        </div>
      ))}

      {items.length === 0 && (
        <div className="px-3 py-8 text-center text-sm text-muted-foreground">
          This folder is empty.
        </div>
      )}
    </div>
  );
}
