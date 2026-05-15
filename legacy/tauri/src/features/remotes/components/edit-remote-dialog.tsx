import { Loader2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { Provider } from "@/lib/rclone/types";
import { useProviders } from "../hooks/use-providers";
import type { RemoteEntry } from "../hooks/use-remotes";
import { useUpdateRemote } from "../hooks/use-remotes";
import { ConfigForm } from "./config-form";

interface EditRemoteDialogProps {
  remote: RemoteEntry | null;
  onClose: () => void;
}

export function EditRemoteDialog({ remote, onClose }: EditRemoteDialogProps) {
  const { data: providers } = useProviders();
  const updateRemote = useUpdateRemote();

  const [configValues, setConfigValues] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);

  // Find the provider matching this remote's type
  const provider: Provider | undefined = providers?.find(
    (p) => p.Name === remote?.type,
  );

  // Pre-fill config values when remote changes
  useEffect(() => {
    if (remote) {
      // Copy existing config, excluding 'type' which is not a user-editable param
      const { type: _, ...rest } = remote.config;
      setConfigValues(rest);
      setError(null);
    }
  }, [remote]);

  const handleConfigChange = useCallback((name: string, value: string) => {
    setConfigValues((prev) => ({ ...prev, [name]: value }));
  }, []);

  const handleSave = useCallback(() => {
    if (!remote) return;

    // Filter out empty values
    const params: Record<string, string> = {};
    for (const [k, v] of Object.entries(configValues)) {
      if (v.trim()) params[k] = v;
    }

    updateRemote.mutate(
      { name: remote.name, parameters: params },
      {
        onSuccess: () => onClose(),
        onError: (err: Error) => setError(err.message),
      },
    );
  }, [remote, configValues, updateRemote, onClose]);

  return (
    <Dialog open={remote !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Edit {remote?.name}</DialogTitle>
          <DialogDescription>
            {provider?.Description ?? `Update ${remote?.type} configuration`}
          </DialogDescription>
        </DialogHeader>

        {provider && (
          <ScrollArea className="max-h-80">
            <div className="grid gap-4 pr-2">
              <ConfigForm
                options={provider.Options}
                values={configValues}
                onChange={handleConfigChange}
              />
            </div>
          </ScrollArea>
        )}

        {!provider && remote && (
          <p className="py-4 text-center text-sm text-muted-foreground">
            Loading provider configuration...
          </p>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button
            onClick={handleSave}
            disabled={updateRemote.isPending}
          >
            {updateRemote.isPending && (
              <Loader2
                className="size-4 animate-spin"
                data-icon="inline-start"
              />
            )}
            {updateRemote.isPending ? "Saving..." : "Save Changes"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
