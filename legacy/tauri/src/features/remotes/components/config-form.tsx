import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { ProviderOption } from "@/lib/rclone/types";

interface ConfigFormProps {
  options: ProviderOption[];
  values: Record<string, string>;
  onChange: (name: string, value: string) => void;
  showAdvanced?: boolean;
}

export function ConfigForm({
  options,
  values,
  onChange,
  showAdvanced = false,
}: ConfigFormProps) {
  const visible = options.filter((o) => showAdvanced || !o.Advanced);

  if (visible.length === 0) {
    return (
      <p className="py-4 text-center text-sm text-muted-foreground">
        No configuration options for this provider.
      </p>
    );
  }

  return (
    <div className="grid gap-4">
      {visible.map((option) => (
        <OptionField
          key={option.Name}
          option={option}
          value={values[option.Name] ?? ""}
          onChange={(v) => onChange(option.Name, v)}
        />
      ))}
    </div>
  );
}

function OptionField({
  option,
  value,
  onChange,
}: {
  option: ProviderOption;
  value: string;
  onChange: (value: string) => void;
}) {
  const hasExamples = option.Examples && option.Examples.length > 0;

  return (
    <div className="grid gap-1.5">
      <Label htmlFor={option.Name}>
        {option.Name}
        {option.Required && (
          <span className="text-destructive" aria-label="required">
            *
          </span>
        )}
      </Label>
      {hasExamples ? (
        <Select value={value} onValueChange={(v) => onChange(v ?? "")}>
          <SelectTrigger className="w-full">
            <SelectValue placeholder="Select..." />
          </SelectTrigger>
          <SelectContent>
            {option.Examples?.map((ex) => (
              <SelectItem key={ex.Value} value={ex.Value || " "}>
                {ex.Value ? `${ex.Value} — ${ex.Help}` : ex.Help}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : (
        <Input
          id={option.Name}
          type={option.IsPassword ? "password" : "text"}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={
            option.Default != null ? String(option.Default) : undefined
          }
        />
      )}
      {option.Help && (
        <p className="text-xs text-muted-foreground">{option.Help}</p>
      )}
    </div>
  );
}
