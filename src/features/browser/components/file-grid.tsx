import { Folder, File } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";
import { cn } from "@/lib/utils";

interface FileGridProps {
  items: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
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
        <div
          key={item.Name}
          className={cn(
            "flex cursor-pointer flex-col items-center gap-1.5 rounded-lg border p-3 text-center transition-colors hover:bg-muted/50",
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
          <span className="w-full truncate text-sm">{item.Name}</span>
          <span className="text-xs text-muted-foreground">
            {item.IsDir ? "Folder" : formatSize(item.Size)}
          </span>
        </div>
      ))}
    </div>
  );
}
