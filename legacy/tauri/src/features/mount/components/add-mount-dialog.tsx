import { homeDir } from "@tauri-apps/api/path";
import { open } from "@tauri-apps/plugin-dialog";
import { FolderOpenIcon, PlusIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { fpAddDomain } from "@/lib/tauri/file-provider";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { getDefaultMountBackend } from "@/lib/platform";
import { useRemotes } from "@/features/remotes/hooks/use-remotes";
import { useMountStore, type VfsMode } from "@/stores/mount-store";

export function AddMountDialog() {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [remote, setRemote] = useState("");
  const [mountPoint, setMountPoint] = useState("");
  const [vfsMode, setVfsMode] = useState<VfsMode>("read-only");
  const [homePath, setHomePath] = useState("");

  const backend = getDefaultMountBackend();
  const { data: remotes } = useRemotes();
  const addConfig = useMountStore((s) => s.addConfig);

  const isFileProvider = backend === "fileprovider";

  useEffect(() => {
    if (backend === "nfs") {
      homeDir().then((p) => setHomePath(p)).catch(() => {});
    }
  }, [backend]);

  useEffect(() => {
    if (isFileProvider && remote) {
      const remoteName = remote.replace(/:$/, "");
      setMountPoint(remoteName);
    } else if (backend === "nfs" && homePath && remote) {
      const remoteName = remote.replace(/:$/, "");
      const base = homePath.endsWith("/") ? homePath : `${homePath}/`;
      setMountPoint(`${base}CloudDrives/${remoteName}`);
    }
  }, [backend, isFileProvider, homePath, remote]);

  async function handleBrowse() {
    const selected = await open({ directory: true, multiple: false });
    if (selected) {
      setMountPoint(selected as string);
    }
  }

  async function handleAdd() {
    if (!remote || !mountPoint) return;

    const remoteName = remote.endsWith(":") ? remote.slice(0, -1) : remote;

    addConfig({
      remote: remote.endsWith(":") ? remote : `${remote}:`,
      mountPoint,
      vfsMode,
      autoMount: false,
      backend,
    });

    if (backend === "fileprovider") {
      try {
        await fpAddDomain(remoteName, mountPoint);
        toast.success(`Registered ${mountPoint} in Finder`);
      } catch (err) {
        toast.error(
          `Failed to register in Finder: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    setRemote("");
    setMountPoint("");
    setVfsMode("read-only");
    setDialogOpen(false);
  }

  return (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogTrigger
        render={
          <Button>
            <PlusIcon data-icon="inline-start" />
            Add Mount
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Mount</DialogTitle>
          <DialogDescription>
            Mount a remote as a local drive on your system.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label>Remote</Label>
            <Select value={remote} onValueChange={(v) => setRemote(v ?? "")}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Select a remote" />
              </SelectTrigger>
              <SelectContent>
                {remotes?.map((r) => (
                  <SelectItem key={r.name} value={r.name}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-2">
            <Label>{isFileProvider ? "Display Name" : "Mount Point"}</Label>
            <div className="flex gap-2">
              <Input
                value={mountPoint}
                onChange={(e) => setMountPoint(e.target.value)}
                placeholder={isFileProvider ? "Google Drive" : "/mnt/remote"}
                className="flex-1 font-mono text-xs"
              />
              {!isFileProvider && (
                <Button variant="outline" size="icon" onClick={handleBrowse}>
                  <FolderOpenIcon />
                </Button>
              )}
            </div>
          </div>

          <div className="grid gap-2">
            <Label>VFS Mode</Label>
            <Select
              value={vfsMode}
              onValueChange={(v) => setVfsMode(v as VfsMode)}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="read-only">Read Only</SelectItem>
                <SelectItem value="read-write">Read Write</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter>
          <DialogClose render={<Button variant="outline" />}>
            Cancel
          </DialogClose>
          <Button onClick={handleAdd} disabled={!remote || !mountPoint}>
            Add
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
