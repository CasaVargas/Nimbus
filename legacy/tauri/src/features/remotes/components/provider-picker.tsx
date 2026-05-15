import { Cloud, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Provider } from "@/lib/rclone/types";

interface ProviderPickerProps {
  providers: Provider[];
  onSelect: (provider: Provider) => void;
}

export function ProviderPicker({ providers, onSelect }: ProviderPickerProps) {
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    if (!search.trim()) return providers;
    const q = search.toLowerCase();
    return providers.filter(
      (p) =>
        p.Name.toLowerCase().includes(q) ||
        p.Description.toLowerCase().includes(q),
    );
  }, [providers, search]);

  return (
    <div className="flex flex-col gap-3">
      <div className="relative">
        <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search providers..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="pl-8"
        />
      </div>
      <ScrollArea className="h-72">
        <div className="grid grid-cols-2 gap-2 pr-2">
          {filtered.map((provider) => (
            <button
              type="button"
              key={provider.Name}
              onClick={() => onSelect(provider)}
              className="flex items-start gap-2.5 rounded-lg border border-border p-2.5 text-left transition-colors hover:bg-muted"
            >
              <Cloud className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
              <div className="min-w-0">
                <div className="truncate text-sm font-medium">
                  {provider.Name}
                </div>
                <div className="line-clamp-2 text-xs text-muted-foreground">
                  {provider.Description}
                </div>
              </div>
            </button>
          ))}
          {filtered.length === 0 && (
            <div className="col-span-2 py-8 text-center text-sm text-muted-foreground">
              No providers match your search.
            </div>
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
