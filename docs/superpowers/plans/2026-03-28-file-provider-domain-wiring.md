# File Provider Domain Registration Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the mount UI to automatically register/unregister File Provider domains when users add or remove fileprovider mounts.

**Architecture:** The add-mount dialog calls `fpAddDomain` after saving the config. The mount-item component calls `fpRemoveDomain` before removing the config. Fileprovider mounts hide the mount/unmount toggle and auto checkbox since Finder drives access. The mount store persist key is renamed from streamcloned to nimbus.

**Tech Stack:** React, Zustand (mount store), Tauri invoke (fpAddDomain/fpRemoveDomain), sonner (toasts)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `src/stores/mount-store.ts` | Rename persist key |
| Modify | `src/features/mount/components/add-mount-dialog.tsx` | Call fpAddDomain on add |
| Modify | `src/features/mount/components/mount-item.tsx` | Call fpRemoveDomain on remove, hide controls |

---

### Task 1: Rename mount store persist key

**Files:**
- Modify: `src/stores/mount-store.ts`

- [ ] **Step 1: Update the persist name**

Change line 45 from:

```typescript
name: "streamcloned-mounts",
```

to:

```typescript
name: "nimbus-mounts",
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/stores/mount-store.ts
git commit -m "chore: rename mount store persist key to nimbus-mounts"
```

---

### Task 2: Call fpAddDomain when adding a fileprovider mount

**Files:**
- Modify: `src/features/mount/components/add-mount-dialog.tsx`

- [ ] **Step 1: Add imports**

Add at the top of the file:

```typescript
import { toast } from "sonner";
import { fpAddDomain } from "@/lib/tauri/file-provider";
```

- [ ] **Step 2: Update handleAdd to call fpAddDomain**

Replace the existing `handleAdd` function (lines 66-81) with:

```typescript
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
```

Key changes: function is now `async`, extracts `remoteName` (without colon) for the domain identifier, calls `fpAddDomain(remoteName, mountPoint)` where `mountPoint` is used as the display name (the dialog label says "Display Name" for fileprovider).

- [ ] **Step 3: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add src/features/mount/components/add-mount-dialog.tsx
git commit -m "feat(fileprovider): register domain in Finder when adding fileprovider mount"
```

---

### Task 3: Call fpRemoveDomain on remove, hide controls for fileprovider

**Files:**
- Modify: `src/features/mount/components/mount-item.tsx`

- [ ] **Step 1: Replace the entire file**

```typescript
import { CircleIcon, Loader2Icon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { fpRemoveDomain } from "@/lib/tauri/file-provider";
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

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4">
      <CircleIcon
        className={`size-3 shrink-0 ${
          isFileProvider || isActive
            ? "fill-green-500 text-green-500"
            : "fill-muted text-muted"
        }`}
      />

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{config.remote}</p>
        <p className="text-xs text-muted-foreground font-mono truncate">
          {isFileProvider ? `Finder — ${config.mountPoint}` : config.mountPoint}
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
```

Key changes from original:
- Import `fpRemoveDomain` and `toast`
- Added `isFileProvider` boolean
- `handleRemove` is now `async`, calls `fpRemoveDomain` before `removeConfig` for fileprovider mounts
- Status indicator shows green for fileprovider mounts (always registered)
- Mount point shows "Finder — {displayName}" for fileprovider mounts
- Auto checkbox hidden for fileprovider
- Mount/Unmount button hidden for fileprovider
- Remove button always enabled for fileprovider (no active mount concept)

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/features/mount/components/mount-item.tsx
git commit -m "feat(fileprovider): unregister domain on remove, hide mount controls for fileprovider"
```
