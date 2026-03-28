import { File, Folder } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";
import { cn } from "@/lib/utils";
import { FileActions } from "./file-actions";
import { FileContextMenu } from "./file-context-menu";
import { InlineRename } from "./inline-rename";

interface FileGridProps {
  items: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
  onDownload: (item: FileItem) => void;
  onRename: (item: FileItem, newName: string) => void;
  onDelete: (item: FileItem) => void;
  onDeleteSelected: () => void;
  onDownloadSelected: () => void;
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

export function FileGrid({
  items,
  selected,
  onSelect,
  onOpen,
  onDownload,
  onRename,
  onDelete,
  onDeleteSelected,
  onDownloadSelected,
  renamingItem,
  onRenameCancel,
}: FileGridProps) {
  if (items.length === 0) {
    return (
      <div className="py-8 text-center text-sm text-muted-foreground">
        This folder is empty.
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
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
              "group/row relative flex cursor-pointer flex-col items-center gap-1.5 rounded-lg border p-3 text-center transition-colors hover:bg-muted/50",
              selected.has(item.Name) && "border-primary bg-primary/10",
            )}
            onClick={(e) => onSelect(item.Name, e)}
            onDoubleClick={() => onOpen(item)}
          >
            {item.IsDir ? (
              <Folder className="size-9 text-blue-500" />
            ) : (
              <File className="size-9 text-muted-foreground" />
            )}
            {renamingItem === item.Name ? (
              <InlineRename
                name={item.Name}
                onConfirm={(newName) => onRename(item, newName)}
                onCancel={onRenameCancel}
                className="text-center"
              />
            ) : (
              <span className="w-full truncate text-sm">{item.Name}</span>
            )}
            <span className="text-xs text-muted-foreground">
              {item.IsDir ? "Folder" : formatSize(item.Size)}
            </span>
            {/* Hover actions overlay */}
            <div className="absolute right-1 top-1 opacity-0 transition-opacity duration-150 group-hover/row:opacity-100">
              <FileActions
                item={item}
                onOpen={onOpen}
                onDownload={onDownload}
              />
            </div>
          </div>
        </FileContextMenu>
      ))}
    </div>
  );
}
