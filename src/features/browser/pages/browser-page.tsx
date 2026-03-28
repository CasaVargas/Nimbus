import { downloadDir } from "@tauri-apps/api/path";
import { open } from "@tauri-apps/plugin-dialog";
import { HardDrive, Trash2, X } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "sonner";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { FileListSkeleton } from "@/components/skeleton";
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
      setRenamingItem(null);
      toast.promise(
        renameFile.mutateAsync({ oldName: item.Name, newName }),
        {
          loading: `Renaming ${item.Name}...`,
          success: `Renamed to ${newName}`,
          error: (err) =>
            `Rename failed: ${err instanceof Error ? err.message : String(err)}`,
        },
      );
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
          <FileListSkeleton />
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
