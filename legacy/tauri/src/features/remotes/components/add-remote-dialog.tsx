import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Loader2 } from "lucide-react";
import { useCallback, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { createRemote } from "@/lib/rclone/remotes";
import type { Provider } from "@/lib/rclone/types";
import { useProviders } from "../hooks/use-providers";
import { ConfigForm } from "./config-form";
import { ProviderPicker } from "./provider-picker";

interface AddRemoteDialogProps {
  open: boolean;
  onClose: () => void;
}

export function AddRemoteDialog({ open, onClose }: AddRemoteDialogProps) {
  const { data: providers } = useProviders();
  const queryClient = useQueryClient();

  const [step, setStep] = useState<"pick" | "configure">("pick");
  const [provider, setProvider] = useState<Provider | null>(null);
  const [remoteName, setRemoteName] = useState("");
  const [configValues, setConfigValues] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setStep("pick");
    setProvider(null);
    setRemoteName("");
    setConfigValues({});
    setError(null);
  }, []);

  const handleClose = useCallback(() => {
    onClose();
    // Reset after animation
    setTimeout(reset, 200);
  }, [onClose, reset]);

  const handleProviderSelect = useCallback((p: Provider) => {
    setProvider(p);
    setStep("configure");
    setError(null);
  }, []);

  const handleBack = useCallback(() => {
    setStep("pick");
    setError(null);
  }, []);

  const handleConfigChange = useCallback((name: string, value: string) => {
    setConfigValues((prev) => ({ ...prev, [name]: value }));
  }, []);

  const createMutation = useMutation({
    mutationFn: async () => {
      if (!provider) throw new Error("No provider selected");
      const name = remoteName.trim();
      if (!name) throw new Error("Remote name is required");
      // Filter out empty values
      const params: Record<string, string> = {};
      for (const [k, v] of Object.entries(configValues)) {
        if (v.trim()) params[k] = v;
      }
      await createRemote(name, provider.Name, params);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["remotes"] });
      handleClose();
    },
    onError: (err: Error) => {
      setError(err.message);
    },
  });

  return (
    <Dialog open={open} onOpenChange={(o) => !o && handleClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          {step === "pick" && (
            <>
              <DialogTitle>Choose a Provider</DialogTitle>
              <DialogDescription>
                Select the type of storage you want to connect.
              </DialogDescription>
            </>
          )}
          {step === "configure" && provider && (
            <>
              <DialogTitle>Configure {provider.Name}</DialogTitle>
              <DialogDescription>{provider.Description}</DialogDescription>
            </>
          )}
        </DialogHeader>

        {step === "pick" && providers && (
          <ProviderPicker
            providers={providers}
            onSelect={handleProviderSelect}
          />
        )}

        {step === "configure" && provider && (
          <ScrollArea className="max-h-80">
            <div className="grid gap-4 pr-2">
              <div className="grid gap-1.5">
                <Label htmlFor="remote-name">
                  Remote Name
                  <span className="text-destructive" aria-label="required">
                    *
                  </span>
                </Label>
                <Input
                  id="remote-name"
                  value={remoteName}
                  onChange={(e) => setRemoteName(e.target.value)}
                  placeholder="e.g. my-drive"
                />
              </div>
              <ConfigForm
                options={provider.Options}
                values={configValues}
                onChange={handleConfigChange}
              />
            </div>
          </ScrollArea>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        {step === "configure" && (
          <DialogFooter>
            <Button variant="outline" onClick={handleBack}>
              <ArrowLeft className="size-4" data-icon="inline-start" />
              Back
            </Button>
            <Button
              onClick={() => createMutation.mutate()}
              disabled={createMutation.isPending || !remoteName.trim()}
            >
              {createMutation.isPending && (
                <Loader2
                  className="size-4 animate-spin"
                  data-icon="inline-start"
                />
              )}
              {createMutation.isPending ? "Creating..." : "Create Remote"}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
