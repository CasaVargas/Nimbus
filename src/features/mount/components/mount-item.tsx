import { CircleIcon, Loader2Icon, RefreshCwIcon } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { fpAddDomain, fpRemoveDomain } from "@/lib/tauri/file-provider";
import type { MountConfig } from "@/stores/mount-store";
import { useMountStore } from "@/stores/mount-store";
import { useMountRemote, useUnmountRemote } from "../hooks/use-mounts";

interface MountItemProps {
  config: MountConfig;
  isActive: boolean;
}

export function MountItem({ config, isActive }: MountItemProps) {
  const toggleAutoMount = useMountStore((s) => s.toggleAutoMount);
  const removeConfig = useMountStore((s) => s.removeConfig);
  const mountMutation = useMountRemote();
  const unmountMutation = useUnmountRemote();
  const [isReregistering, setIsReregistering] = useState(false);

  const isLoading = mountMutation.isPending || unmountMutation.isPending;
  const isFileProvider = config.backend === "fileprovider";

  function handleToggleMount() {
    if (isActive) {
      unmountMutation.mutate(
        { mountPoint: config.mountPoint, backend: config.backend },
        { onError: (e) => toast.error(`Unmount failed: ${e.message || e}`) },
      );
    } else {
      mountMutation.mutate(
        {
          fs: config.remote,
          mountPoint: config.mountPoint,
          vfsOpt: config.vfsMode === "read-only" ? { readOnly: true } : undefined,
          backend: config.backend,
        },
        { onError: (e) => toast.error(`Mount failed: ${e.message || e}`) },
      );
    }
  }

  async function handleRemove() {
    if (isFileProvider) {
      const remoteName = config.remote.replace(/:$/, "");
      try {
        await fpRemoveDomain(remoteName);
        toast.success(`Removed ${config.mountPoint} from Finder`);
      } catch (err) {
        toast.error(
          `Failed to remove from Finder: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    removeConfig(config.mountPoint);
  }

  async function handleReregister() {
    const remoteName = config.remote.replace(/:$/, "");
    setIsReregistering(true);
    try {
      await fpAddDomain(remoteName, config.mountPoint);
      toast.success(`Re-registered ${config.mountPoint} in Finder`);
    } catch (err) {
      toast.error(
        `Failed to re-register: ${err instanceof Error ? err.message : String(err)}`,
      );
    } finally {
      setIsReregistering(false);
    }
  }

  const isRegistered = isFileProvider && isActive;
  const needsReregister = isFileProvider && !isActive;

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4">
      <CircleIcon
        className={`size-3 shrink-0 ${
          isRegistered || (!isFileProvider && isActive)
            ? "fill-green-500 text-green-500"
            : needsReregister
              ? "fill-red-500 text-red-500"
              : "fill-muted text-muted"
        }`}
      />

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{config.remote}</p>
        <p className="text-xs text-muted-foreground font-mono truncate">
          {isFileProvider
            ? isRegistered
              ? `Finder — ${config.mountPoint}`
              : `Not registered — ${config.mountPoint}`
            : config.mountPoint}
        </p>
      </div>

      {!isFileProvider && (
        <label className="flex items-center gap-2 text-xs text-muted-foreground cursor-pointer select-none">
          <input
            type="checkbox"
            checked={config.autoMount}
            onChange={() => toggleAutoMount(config.mountPoint)}
            className="rounded"
          />
          Auto
        </label>
      )}

      {!isFileProvider && (
        <Button
          variant={isActive ? "destructive" : "outline"}
          size="sm"
          onClick={handleToggleMount}
          disabled={isLoading}
        >
          {isLoading ? (
            <Loader2Icon className="size-3.5 animate-spin" />
          ) : isActive ? (
            "Unmount"
          ) : (
            "Mount"
          )}
        </Button>
      )}

      {needsReregister && (
        <Button
          variant="outline"
          size="sm"
          onClick={handleReregister}
          disabled={isReregistering}
        >
          {isReregistering ? (
            <Loader2Icon className="size-3.5 animate-spin" />
          ) : (
            <>
              <RefreshCwIcon className="size-3.5" />
              Re-register
            </>
          )}
        </Button>
      )}

      <Button
        variant="ghost"
        size="sm"
        onClick={handleRemove}
        disabled={!isFileProvider && isActive}
      >
        Remove
      </Button>
    </div>
  );
}
