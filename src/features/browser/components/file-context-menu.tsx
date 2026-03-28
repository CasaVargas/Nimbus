import { ContextMenu } from "@base-ui/react/context-menu";
import { Menu } from "@base-ui/react/menu";
import { Download, ExternalLink, Pencil, Trash2 } from "lucide-react";
import type { FileItem } from "@/lib/rclone/types";
import { cn } from "@/lib/utils";

interface FileContextMenuProps {
  item: FileItem;
  isMultiSelect: boolean;
  selectedCount: number;
  onOpen: (item: FileItem) => void;
  onDownload: (item: FileItem) => void;
  onRename: (item: FileItem) => void;
  onDelete: (item: FileItem) => void;
  onDeleteSelected: () => void;
  onDownloadSelected: () => void;
  children: React.ReactNode;
}

const itemClass =
  "flex cursor-default items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-hidden select-none data-highlighted:bg-accent data-highlighted:text-accent-foreground";

const destructiveClass =
  "flex cursor-default items-center gap-2 rounded-md px-2 py-1.5 text-sm text-destructive outline-hidden select-none data-highlighted:bg-destructive/10 data-highlighted:text-destructive";

export function FileContextMenu({
  item,
  isMultiSelect,
  selectedCount,
  onOpen,
  onDownload,
  onRename,
  onDelete,
  onDeleteSelected,
  onDownloadSelected,
  children,
}: FileContextMenuProps) {
  return (
    <ContextMenu.Root>
      <ContextMenu.Trigger className="contents">
        {children}
      </ContextMenu.Trigger>
      <Menu.Portal>
        <Menu.Positioner
          className="isolate z-50 outline-none"
          sideOffset={4}
        >
          <Menu.Popup
            className={cn(
              "min-w-40 origin-(--transform-origin) rounded-lg bg-popover p-1 text-popover-foreground shadow-md ring-1 ring-foreground/10",
              "data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95",
              "data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
            )}
          >
            {isMultiSelect ? (
              <>
                <Menu.Item
                  className={itemClass}
                  onSelect={onDownloadSelected}
                >
                  <Download className="size-4" />
                  Download {selectedCount} items
                </Menu.Item>
                <Menu.Separator className="-mx-1 my-1 h-px bg-border" />
                <Menu.Item
                  className={destructiveClass}
                  onSelect={onDeleteSelected}
                >
                  <Trash2 className="size-4" />
                  Delete {selectedCount} items
                </Menu.Item>
              </>
            ) : (
              <>
                <Menu.Item
                  className={itemClass}
                  onSelect={() => onOpen(item)}
                >
                  <ExternalLink className="size-4" />
                  Open
                </Menu.Item>
                {!item.IsDir && (
                  <Menu.Item
                    className={itemClass}
                    onSelect={() => onDownload(item)}
                  >
                    <Download className="size-4" />
                    Download
                  </Menu.Item>
                )}
                <Menu.Item
                  className={itemClass}
                  onSelect={() => onRename(item)}
                >
                  <Pencil className="size-4" />
                  Rename
                </Menu.Item>
                <Menu.Separator className="-mx-1 my-1 h-px bg-border" />
                <Menu.Item
                  className={destructiveClass}
                  onSelect={() => onDelete(item)}
                >
                  <Trash2 className="size-4" />
                  Delete
                </Menu.Item>
              </>
            )}
          </Menu.Popup>
        </Menu.Positioner>
      </Menu.Portal>
    </ContextMenu.Root>
  );
}
