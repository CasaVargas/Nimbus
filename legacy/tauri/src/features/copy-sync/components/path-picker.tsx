import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useRemotes } from "@/features/remotes/hooks/use-remotes";

interface PathPickerProps {
  label: string;
  remote: string;
  path: string;
  onRemoteChange: (remote: string) => void;
  onPathChange: (path: string) => void;
}

export function PathPicker({
  label,
  remote,
  path,
  onRemoteChange,
  onPathChange,
}: PathPickerProps) {
  const { data: remotes, isLoading } = useRemotes();

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="flex gap-2">
        <Select
          value={remote}
          onValueChange={(v) => {
            if (v) onRemoteChange(v);
          }}
        >
          <SelectTrigger className="w-48">
            <SelectValue
              placeholder={isLoading ? "Loading..." : "Select remote"}
            />
          </SelectTrigger>
          <SelectContent>
            {remotes?.map((r) => (
              <SelectItem key={r.name} value={r.name}>
                {r.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Input
          className="flex-1"
          placeholder="path/to/folder"
          value={path}
          onChange={(e) => onPathChange(e.target.value)}
        />
      </div>
    </div>
  );
}
