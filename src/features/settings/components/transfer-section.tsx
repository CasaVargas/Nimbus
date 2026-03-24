import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAppStore } from "@/stores/app-store";

export function TransferSection() {
  const concurrentTransfers = useAppStore((s) => s.concurrentTransfers);
  const setConcurrentTransfers = useAppStore((s) => s.setConcurrentTransfers);
  const bandwidthLimit = useAppStore((s) => s.bandwidthLimit);
  const setBandwidthLimit = useAppStore((s) => s.setBandwidthLimit);

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">Transfers</h3>
        <p className="text-xs text-muted-foreground">
          Control transfer speed and parallelism.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label>Concurrent Transfers</Label>
          <Input
            type="number"
            min={1}
            max={32}
            value={concurrentTransfers}
            onChange={(e) =>
              setConcurrentTransfers(Number.parseInt(e.target.value, 10) || 4)
            }
            className="w-24"
          />
        </div>
        <div className="grid gap-2">
          <Label>Bandwidth Limit</Label>
          <Input
            value={bandwidthLimit}
            onChange={(e) => setBandwidthLimit(e.target.value)}
            placeholder="off (e.g. 10M, 1G)"
            className="w-48 font-mono text-xs"
          />
        </div>
      </div>
    </div>
  );
}
