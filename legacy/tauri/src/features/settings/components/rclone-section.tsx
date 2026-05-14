import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAppStore } from "@/stores/app-store";

export function RcloneSection() {
  const rclonePort = useAppStore((s) => s.rclonePort);
  const rcloneBinaryPath = useAppStore((s) => s.rcloneBinaryPath);
  const setRcloneBinaryPath = useAppStore((s) => s.setRcloneBinaryPath);

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">Rclone</h3>
        <p className="text-xs text-muted-foreground">
          Configure the rclone backend connection.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label>API Port</Label>
          <Input
            value={rclonePort}
            disabled
            className="w-48 font-mono text-xs"
          />
        </div>
        <div className="grid gap-2">
          <Label>Binary Path</Label>
          <Input
            value={rcloneBinaryPath}
            onChange={(e) => setRcloneBinaryPath(e.target.value)}
            placeholder="rclone (uses PATH)"
            className="w-64 font-mono text-xs"
          />
        </div>
      </div>
    </div>
  );
}
