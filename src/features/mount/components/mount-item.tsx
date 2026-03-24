import { CircleIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
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

  const isLoading = mountMutation.isPending || unmountMutation.isPending;

  function handleToggleMount() {
    if (isActive) {
      unmountMutation.mutate(config.mountPoint);
    } else {
      mountMutation.mutate({
        fs: config.remote,
        mountPoint: config.mountPoint,
        vfsOpt: config.vfsMode === "read-only" ? { readOnly: true } : undefined,
      });
    }
  }

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4">
      <CircleIcon
        className={`size-3 shrink-0 ${isActive ? "fill-green-500 text-green-500" : "fill-muted text-muted"}`}
      />

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{config.remote}</p>
        <p className="text-xs text-muted-foreground font-mono truncate">
          {config.mountPoint}
        </p>
      </div>

      <label className="flex items-center gap-2 text-xs text-muted-foreground cursor-pointer select-none">
        <input
          type="checkbox"
          checked={config.autoMount}
          onChange={() => toggleAutoMount(config.mountPoint)}
          className="rounded"
        />
        Auto
      </label>

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

      <Button
        variant="ghost"
        size="sm"
        onClick={() => removeConfig(config.mountPoint)}
      >
        Remove
      </Button>
    </div>
  );
}
