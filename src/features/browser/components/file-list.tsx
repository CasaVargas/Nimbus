import { ChevronDown, ChevronUp, File, Folder } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";
import { cn } from "@/lib/utils";
import { FileActions } from "./file-actions";
import { FileContextMenu } from "./file-context-menu";
import { InlineRename } from "./inline-rename";

export type SortField = "name" | "size" | "modified";
export type SortDir = "asc" | "desc";

interface FileListProps {
  items: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
  onDownload: (item: FileItem) => void;
  onRename: (item: FileItem, newName: string) => void;
  onDelete: (item: FileItem) => void;
  onDeleteSelected: () => void;
  onDownloadSelected: () => void;
  sortBy: SortField;
  sortDir: SortDir;
  onSort: (field: SortField) => void;
  renamingItem: string | null;
  onRenameCancel: () => void;
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
  onDownload,
  onRename,
  onDelete,
  onDeleteSelected,
  onDownloadSelected,
  sortBy,
  sortDir,
  onSort,
  renamingItem,
  onRenameCancel,
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
        <FileContextMenu
          key={item.Name}
          item={item}
          isMultiSelect={selected.size > 1 && selected.has(item.Name)}
          selectedCount={selected.size}
          onOpen={onOpen}
          onDownload={onDownload}
          onRename={(i) => onRename(i, "")}
          onDelete={onDelete}
          onDeleteSelected={onDeleteSelected}
          onDownloadSelected={onDownloadSelected}
        >
          <div
            className={cn(
              "group/row grid cursor-pointer items-center gap-2 border-b px-3 py-1.5 text-sm last:border-b-0 hover:bg-muted/50",
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
              {renamingItem === item.Name ? (
                <InlineRename
                  name={item.Name}
                  onConfirm={(newName) => onRename(item, newName)}
                  onCancel={onRenameCancel}
                />
              ) : (
                <span className="truncate">{item.Name}</span>
              )}
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">
                {item.IsDir ? "--" : formatSize(item.Size)}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">
                {formatDate(item.ModTime)}
              </span>
              <FileActions
                item={item}
                onOpen={onOpen}
                onDownload={onDownload}
              />
            </div>
          </div>
        </FileContextMenu>
      ))}

      {items.length === 0 && (
        <div className="px-3 py-8 text-center text-sm text-muted-foreground">
          This folder is empty.
        </div>
      )}
    </div>
  );
}
