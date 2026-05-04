import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { useLaunchAtLogin } from "@/hooks/use-launch-at-login";

export function GeneralSection() {
  const { enabled, loading, error, toggle } = useLaunchAtLogin();

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">General</h3>
        <p className="text-xs text-muted-foreground">
          Startup and system integration.
        </p>
      </div>
      <div className="flex items-center gap-3">
        <Switch
          id="launch-at-login"
          checked={enabled}
          disabled={loading}
          onCheckedChange={() => {
            void toggle();
          }}
        />
        <Label htmlFor="launch-at-login">Launch Nimbus at login</Label>
      </div>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
