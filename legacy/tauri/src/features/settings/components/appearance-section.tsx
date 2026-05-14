import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { type Theme, useAppStore } from "@/stores/app-store";

export function AppearanceSection() {
  const theme = useAppStore((s) => s.theme);
  const setTheme = useAppStore((s) => s.setTheme);

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">Appearance</h3>
        <p className="text-xs text-muted-foreground">
          Customize the look and feel of the app.
        </p>
      </div>
      <div className="grid gap-2">
        <Label>Theme</Label>
        <Select value={theme} onValueChange={(v) => setTheme(v as Theme)}>
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="light">Light</SelectItem>
            <SelectItem value="dark">Dark</SelectItem>
            <SelectItem value="system">System</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>
  );
}
