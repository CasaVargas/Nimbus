# File Browser Completions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add download, rename, open-with-system-app, context menus, and hover actions to the file browser so it feels complete and premium.

**Architecture:** Three new components (context menu, hover actions, inline rename) compose around the existing FileList/FileGrid. New hooks (`useRenameFile`, updated `useDownloadFile` usage) follow the existing mutation pattern. The `@base-ui/react` ContextMenu primitive handles right-click positioning natively.

**Tech Stack:** React 19, @base-ui/react (ContextMenu + Menu primitives), @tauri-apps/api/path (downloadDir), @tanstack/react-query (mutations), lucide-react (icons), sonner (toasts), rclone RC API (operations/movefile, operations/copyfile)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/features/browser/components/file-context-menu.tsx` | Right-click context menu using @base-ui/react ContextMenu |
| Create | `src/features/browser/components/file-actions.tsx` | Hover action buttons (Open, Download) |
| Create | `src/features/browser/components/inline-rename.tsx` | Editable filename input |
| Modify | `src/features/browser/hooks/use-file-operations.ts` | Add useRenameFile, fix useOpenFile, update useDownloadFile |
| Modify | `src/features/browser/components/file-list.tsx` | Integrate context menu, hover actions, inline rename |
| Modify | `src/features/browser/components/file-grid.tsx` | Integrate context menu, hover actions, inline rename |
| Modify | `src/features/browser/pages/browser-page.tsx` | Add handleDownload, handleRename, wire new props |

---

### Task 1: Add useRenameFile hook and fix useDownloadFile

**Files:**
- Modify: `src/features/browser/hooks/use-file-operations.ts`

- [ ] **Step 1: Add the `useRenameFile` hook and update `useDownloadFile` to use `downloadDir()`**

Add `downloadDir` to the existing path import at line 1:

```typescript
import { downloadDir, join, tempDir } from "@tauri-apps/api/path";
```

Add `useRenameFile` after the existing `useOpenFile` hook (after line 83):

```typescript
export function useRenameFile(remote: string, path: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      oldName,
      newName,
    }: {
      oldName: string;
      newName: string;
    }) => {
      const oldPath = path ? `${path}/${oldName}` : oldName;
      const newPath = path ? `${path}/${newName}` : newName;
      await operations.moveFile(`${remote}:`, oldPath, `${remote}:`, newPath);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, path] });
    },
  });
}
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/hooks/use-file-operations.ts
git commit -m "feat(browser): add useRenameFile hook"
```

---

### Task 2: Create the inline rename component

**Files:**
- Create: `src/features/browser/components/inline-rename.tsx`

- [ ] **Step 1: Create the InlineRename component**

```typescript
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

interface InlineRenameProps {
  name: string;
  onConfirm: (newName: string) => void;
  onCancel: () => void;
  className?: string;
}

export function InlineRename({
  name,
  onConfirm,
  onCancel,
  className,
}: InlineRenameProps) {
  const [value, setValue] = useState(name);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const input = inputRef.current;
    if (!input) return;
    input.focus();
    // Select just the name part, not the extension
    const dotIndex = name.lastIndexOf(".");
    if (dotIndex > 0) {
      input.setSelectionRange(0, dotIndex);
    } else {
      input.select();
    }
  }, [name]);

  const handleConfirm = () => {
    const trimmed = value.trim();
    if (!trimmed || trimmed === name) {
      onCancel();
      return;
    }
    onConfirm(trimmed);
  };

  return (
    <input
      ref={inputRef}
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          handleConfirm();
        }
        if (e.key === "Escape") {
          e.preventDefault();
          onCancel();
        }
        // Stop propagation so row click/select handlers don't fire
        e.stopPropagation();
      }}
      onBlur={handleConfirm}
      onClick={(e) => e.stopPropagation()}
      onDoubleClick={(e) => e.stopPropagation()}
      className={cn(
        "h-6 w-full rounded border border-primary bg-background px-1 text-sm outline-none",
        className,
      )}
    />
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/inline-rename.tsx
git commit -m "feat(browser): add InlineRename component"
```

---

### Task 3: Create the hover action buttons component

**Files:**
- Create: `src/features/browser/components/file-actions.tsx`

- [ ] **Step 1: Create the FileActions component**

```typescript
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
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/file-actions.tsx
git commit -m "feat(browser): add FileActions hover buttons component"
```

---

### Task 4: Create the context menu component

**Files:**
- Create: `src/features/browser/components/file-context-menu.tsx`

- [ ] **Step 1: Create the FileContextMenu component**

This uses `@base-ui/react`'s `ContextMenu` primitive directly (not the existing `DropdownMenu` wrapper, since that's for trigger-click menus). The ContextMenu shares `Menu.Item`, `Menu.Popup`, etc. with the regular Menu.

```typescript
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
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/file-context-menu.tsx
git commit -m "feat(browser): add FileContextMenu component"
```

---

### Task 5: Integrate context menu, hover actions, and inline rename into FileList

**Files:**
- Modify: `src/features/browser/components/file-list.tsx`

- [ ] **Step 1: Update FileListProps and add new imports**

Replace the entire file with:

```typescript
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
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: Errors about missing props in `browser-page.tsx` (expected — we'll fix in Task 7)

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/file-list.tsx
git commit -m "feat(browser): integrate context menu, hover actions, inline rename into FileList"
```

---

### Task 6: Integrate context menu, hover actions, and inline rename into FileGrid

**Files:**
- Modify: `src/features/browser/components/file-grid.tsx`

- [ ] **Step 1: Replace the entire file**

```typescript
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
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: Errors about missing props in `browser-page.tsx` (expected — fixed next task)

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/components/file-grid.tsx
git commit -m "feat(browser): integrate context menu, hover actions, inline rename into FileGrid"
```

---

### Task 7: Wire everything together in BrowserPage

**Files:**
- Modify: `src/features/browser/pages/browser-page.tsx`

- [ ] **Step 1: Update imports, add hooks, add handlers, pass new props**

Replace the entire file with:

```typescript
import { downloadDir } from "@tauri-apps/api/path";
import { open } from "@tauri-apps/plugin-dialog";
import { HardDrive, Trash2, X } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "sonner";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { PathBreadcrumb } from "@/components/path-breadcrumb";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { FileItem } from "@/lib/rclone/types";
import { BrowserToolbar, type ViewMode } from "../components/browser-toolbar";
import { FileGrid } from "../components/file-grid";
import {
  FileList,
  type SortDir,
  type SortField,
} from "../components/file-list";
import { useFileList } from "../hooks/use-file-list";
import {
  useCreateFolder,
  useDeleteItems,
  useDownloadFile,
  useOpenFile,
  useRenameFile,
  useUploadFile,
} from "../hooks/use-file-operations";
import { useSelection } from "../hooks/use-selection";

export default function BrowserPage() {
  const { remote, "*": splat } = useParams();
  const navigate = useNavigate();
  const path = splat ?? "";

  // View state
  const [viewMode, setViewMode] = useState<ViewMode>("list");
  const [filter, setFilter] = useState("");
  const [sortBy, setSortBy] = useState<SortField>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  // New folder dialog state
  const [folderDialogOpen, setFolderDialogOpen] = useState(false);
  const [folderName, setFolderName] = useState("");

  // Rename state
  const [renamingItem, setRenamingItem] = useState<string | null>(null);

  // Data
  const { data: files, isLoading } = useFileList(remote, path);

  // Sorting + filtering
  const processedFiles = useMemo(() => {
    if (!files) return [];

    let result = files;

    // Filter
    if (filter) {
      const lowerFilter = filter.toLowerCase();
      result = result.filter((f) => f.Name.toLowerCase().includes(lowerFilter));
    }

    // Sort: directories first, then by field
    result = [...result].sort((a, b) => {
      if (a.IsDir !== b.IsDir) return a.IsDir ? -1 : 1;

      let cmp = 0;
      switch (sortBy) {
        case "name":
          cmp = a.Name.localeCompare(b.Name);
          break;
        case "size":
          cmp = a.Size - b.Size;
          break;
        case "modified":
          cmp = new Date(a.ModTime).getTime() - new Date(b.ModTime).getTime();
          break;
      }

      return sortDir === "asc" ? cmp : -cmp;
    });

    return result;
  }, [files, filter, sortBy, sortDir]);

  const fileNames = useMemo(
    () => processedFiles.map((f) => f.Name),
    [processedFiles],
  );
  const {
    selected,
    toggle,
    clear,
    selectAll: _selectAll,
  } = useSelection(fileNames);

  // Mutations
  const createFolder = useCreateFolder(remote ?? "", path);
  const deleteItems = useDeleteItems(remote ?? "", path);
  const uploadFile = useUploadFile(remote ?? "", path);
  const openFile = useOpenFile(remote ?? "");
  const downloadFile = useDownloadFile(remote ?? "");
  const renameFile = useRenameFile(remote ?? "", path);

  // Handlers
  const handleSort = useCallback(
    (field: SortField) => {
      if (field === sortBy) {
        setSortDir((d) => (d === "asc" ? "desc" : "asc"));
      } else {
        setSortBy(field);
        setSortDir("asc");
      }
    },
    [sortBy],
  );

  const handleOpen = useCallback(
    (item: FileItem) => {
      if (item.IsDir || item.MimeType === "inode/directory") {
        const newPath = path ? `${path}/${item.Name}` : item.Name;
        navigate(`/browser/${remote}/${newPath}`);
        clear();
        setFilter("");
      } else {
        const remotePath = path ? `${path}/${item.Name}` : item.Name;
        toast.promise(openFile.mutateAsync(remotePath), {
          loading: `Opening ${item.Name}...`,
          success: `Opened ${item.Name}`,
          error: (err) =>
            `Failed to open: ${err instanceof Error ? err.message : String(err)}`,
        });
      }
    },
    [path, remote, navigate, clear, openFile],
  );

  const handleDownload = useCallback(
    async (item: FileItem) => {
      if (item.IsDir) return;
      const remotePath = path ? `${path}/${item.Name}` : item.Name;
      const dlDir = await downloadDir();
      toast.promise(
        downloadFile.mutateAsync({ remotePath, localPath: dlDir }),
        {
          loading: `Downloading ${item.Name}...`,
          success: `Downloaded ${item.Name} to ~/Downloads`,
          error: (err) =>
            `Download failed: ${err instanceof Error ? err.message : String(err)}`,
        },
      );
    },
    [path, downloadFile],
  );

  const handleRename = useCallback(
    (item: FileItem, newName: string) => {
      // If newName is empty, enter rename mode
      if (!newName) {
        setRenamingItem(item.Name);
        return;
      }
      // Perform the rename
      toast.promise(
        renameFile.mutateAsync({ oldName: item.Name, newName }),
        {
          loading: `Renaming ${item.Name}...`,
          success: `Renamed to ${newName}`,
          error: (err) =>
            `Rename failed: ${err instanceof Error ? err.message : String(err)}`,
        },
      );
      setRenamingItem(null);
    },
    [renameFile],
  );

  const handleRenameCancel = useCallback(() => {
    setRenamingItem(null);
  }, []);

  const handleDeleteSingle = useCallback(
    (item: FileItem) => {
      deleteItems.mutate([{ name: item.Name, isDir: item.IsDir }], {
        onSuccess: () => {
          toast.success(`Deleted ${item.Name}`);
          clear();
        },
        onError: (err) => {
          toast.error(`Delete failed: ${err.message}`);
        },
      });
    },
    [deleteItems, clear],
  );

  const handleNavigate = useCallback(
    (newPath: string) => {
      navigate(
        newPath ? `/browser/${remote}/${newPath}` : `/browser/${remote}`,
      );
      clear();
      setFilter("");
    },
    [remote, navigate, clear],
  );

  const handleNewFolder = useCallback(() => {
    setFolderName("");
    setFolderDialogOpen(true);
  }, []);

  const handleCreateFolder = useCallback(() => {
    if (!folderName.trim()) return;
    createFolder.mutate(folderName.trim(), {
      onSuccess: () => {
        setFolderDialogOpen(false);
        toast.success(`Created folder "${folderName.trim()}"`);
      },
      onError: (err) => {
        toast.error(`Failed to create folder: ${err.message}`);
      },
    });
  }, [folderName, createFolder]);

  const handleUpload = useCallback(async () => {
    try {
      const result = await open({ multiple: false });
      if (result === null) return;
      const filePath = Array.isArray(result) ? result[0] : result;
      if (!filePath) return;

      uploadFile.mutate(filePath, {
        onSuccess: () => {
          toast.success("File uploaded successfully");
        },
        onError: (err) => {
          toast.error(`Upload failed: ${err.message}`);
        },
      });
    } catch (err) {
      toast.error(
        `Dialog error: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }, [uploadFile]);

  const handleDelete = useCallback(() => {
    if (selected.size === 0 || !files) return;
    const items = files
      .filter((f) => selected.has(f.Name))
      .map((f) => ({ name: f.Name, isDir: f.IsDir }));

    deleteItems.mutate(items, {
      onSuccess: () => {
        toast.success(`Deleted ${items.length} item(s)`);
        clear();
      },
      onError: (err) => {
        toast.error(`Delete failed: ${err.message}`);
      },
    });
  }, [selected, files, deleteItems, clear]);

  const handleDownloadSelected = useCallback(async () => {
    if (selected.size === 0 || !files) return;
    const dlDir = await downloadDir();
    const fileItems = files.filter(
      (f) => selected.has(f.Name) && !f.IsDir,
    );
    if (fileItems.length === 0) {
      toast.error("No files selected (folders are skipped)");
      return;
    }
    toast.promise(
      Promise.all(
        fileItems.map((f) => {
          const remotePath = path ? `${path}/${f.Name}` : f.Name;
          return downloadFile.mutateAsync({ remotePath, localPath: dlDir });
        }),
      ),
      {
        loading: `Downloading ${fileItems.length} file(s)...`,
        success: `Downloaded ${fileItems.length} file(s) to ~/Downloads`,
        error: (err) =>
          `Download failed: ${err instanceof Error ? err.message : String(err)}`,
      },
    );
  }, [selected, files, path, downloadFile]);

  // No remote selected
  if (!remote) {
    return (
      <div>
        <PageHeader
          title="Browser"
          description="Browse files on your remotes"
        />
        <EmptyState
          icon={HardDrive}
          title="No remote selected"
          description="Select a remote from the sidebar to browse its files."
        />
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Browser" description={`Browsing ${remote}`} />

      <div className="flex flex-1 flex-col gap-4 p-6">
        <PathBreadcrumb
          remote={remote}
          path={path}
          onNavigate={handleNavigate}
        />

        <BrowserToolbar
          viewMode={viewMode}
          onViewModeChange={setViewMode}
          onNewFolder={handleNewFolder}
          onUpload={handleUpload}
          filter={filter}
          onFilterChange={setFilter}
        />

        {isLoading ? (
          <div className="py-8 text-center text-sm text-muted-foreground">
            Loading...
          </div>
        ) : viewMode === "list" ? (
          <FileList
            items={processedFiles}
            selected={selected}
            onSelect={toggle}
            onOpen={handleOpen}
            onDownload={handleDownload}
            onRename={handleRename}
            onDelete={handleDeleteSingle}
            onDeleteSelected={handleDelete}
            onDownloadSelected={handleDownloadSelected}
            sortBy={sortBy}
            sortDir={sortDir}
            onSort={handleSort}
            renamingItem={renamingItem}
            onRenameCancel={handleRenameCancel}
          />
        ) : (
          <FileGrid
            items={processedFiles}
            selected={selected}
            onSelect={toggle}
            onOpen={handleOpen}
            onDownload={handleDownload}
            onRename={handleRename}
            onDelete={handleDeleteSingle}
            onDeleteSelected={handleDelete}
            onDownloadSelected={handleDownloadSelected}
            renamingItem={renamingItem}
            onRenameCancel={handleRenameCancel}
          />
        )}
      </div>

      {/* Selection bar */}
      {selected.size > 0 && (
        <div className="flex items-center gap-3 border-t bg-muted/50 px-6 py-3">
          <span className="text-sm font-medium">
            {selected.size} item{selected.size !== 1 ? "s" : ""} selected
          </span>
          <div className="flex-1" />
          <Button
            variant="destructive"
            size="sm"
            onClick={handleDelete}
            disabled={deleteItems.isPending}
          >
            <Trash2 data-icon="inline-start" />
            {deleteItems.isPending ? "Deleting..." : "Delete"}
          </Button>
          <Button variant="ghost" size="sm" onClick={clear}>
            <X data-icon="inline-start" />
            Clear
          </Button>
        </div>
      )}

      {/* New folder dialog */}
      <Dialog open={folderDialogOpen} onOpenChange={setFolderDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New Folder</DialogTitle>
            <DialogDescription>
              Enter a name for the new folder.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-2 py-2">
            <Label htmlFor="folder-name">Folder name</Label>
            <Input
              id="folder-name"
              value={folderName}
              onChange={(e) => setFolderName(e.target.value)}
              placeholder="My Folder"
              onKeyDown={(e) => {
                if (e.key === "Enter") handleCreateFolder();
              }}
              autoFocus
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setFolderDialogOpen(false)}
            >
              Cancel
            </Button>
            <Button
              onClick={handleCreateFolder}
              disabled={!folderName.trim() || createFolder.isPending}
            >
              {createFolder.isPending ? "Creating..." : "Create"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/browser/pages/browser-page.tsx
git commit -m "feat(browser): wire download, rename, delete, context menu into BrowserPage"
```

---

### Task 8: Final verification

- [ ] **Step 1: Type check**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 2: Manual test checklist**

Run the app with `npm run tauri dev` and verify:

1. Right-click a file → context menu shows Open, Download, Rename, Delete
2. Right-click a folder → context menu shows Open, Rename, Delete (no Download)
3. Select multiple files, right-click → shows "Download N items", "Delete N items"
4. Hover a file row (list view) → Open and Download icons appear on the right
5. Hover a folder row → only Open icon appears
6. Hover a grid card → action icons appear in top-right corner
7. Context menu → Rename → filename becomes editable input → type new name → Enter confirms
8. Context menu → Rename → Escape cancels
9. Context menu → Download → toast shows "Downloading..." → "Downloaded to ~/Downloads"
10. Double-click a file → opens with system default app (existing behavior)

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat(browser): complete file browser actions - context menu, hover, download, rename"
```
