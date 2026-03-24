import { useMemo } from "react";
import { HardDriveIcon } from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { EmptyState } from "@/components/empty-state";
import { useMountStore } from "@/stores/mount-store";
import { useActiveMounts } from "../hooks/use-mounts";
import { MountItem } from "../components/mount-item";
import { AddMountDialog } from "../components/add-mount-dialog";

export default function MountPage() {
  const configs = useMountStore((s) => s.configs);
  const { data: activeMounts } = useActiveMounts();

  const activeMountPoints = useMemo(() => {
    const set = new Set<string>();
    for (const m of activeMounts ?? []) {
      set.add(m.MountPoint);
    }
    return set;
  }, [activeMounts]);

  return (
    <div>
      <PageHeader
        title="Mounts"
        description="Mount remotes as local drives"
        actions={<AddMountDialog />}
      />
      <div className="p-6">
        {configs.length === 0 ? (
          <EmptyState
            icon={HardDriveIcon}
            title="No mounts configured"
            description="Add a mount to access your remote storage as a local drive."
            action={<AddMountDialog />}
          />
        ) : (
          <div className="grid gap-3">
            {configs.map((config) => (
              <MountItem
                key={config.mountPoint}
                config={config}
                isActive={activeMountPoints.has(config.mountPoint)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
