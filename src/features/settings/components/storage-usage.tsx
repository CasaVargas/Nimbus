import { HardDrive } from "lucide-react";

export function StorageUsage() {
  // Storage usage data will come from a Tauri command once the
  // File Provider backend is implemented. For now, show a placeholder.
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <HardDrive className="h-4 w-4 text-muted-foreground" />
        <h3 className="text-sm font-medium">Local Cache</h3>
      </div>
      <p className="text-sm text-muted-foreground">
        Cache usage information will be available when File Provider is active.
      </p>
    </div>
  );
}
