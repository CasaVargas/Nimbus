import { useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { open as openFilePicker } from "@tauri-apps/plugin-dialog";
import { Loader2 } from "lucide-react";
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
import { type ParsedRemote, parseRcloneConf } from "@/lib/rclone/ini-parser";
import { createRemote } from "@/lib/rclone/remotes";
import { useRemotes } from "../hooks/use-remotes";

interface ImportConfigDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface RemoteRow {
  parsed: ParsedRemote;
  selected: boolean;
  /** Renamed value; empty string means use original name */
  rename: string;
  hasConflict: boolean;
}

type Step = "idle" | "review" | "importing" | "done";

export function ImportConfigDialog({
  open,
  onOpenChange,
}: ImportConfigDialogProps) {
  const queryClient = useQueryClient();
  const { data: existingRemotes } = useRemotes();

  const [step, setStep] = useState<Step>("idle");
  const [rows, setRows] = useState<RemoteRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [importErrors, setImportErrors] = useState<string[]>([]);

  const reset = useCallback(() => {
    setStep("idle");
    setRows([]);
    setError(null);
    setImportErrors([]);
  }, []);

  const handleClose = useCallback(() => {
    onOpenChange(false);
    setTimeout(reset, 200);
  }, [onOpenChange, reset]);

  const handlePickFile = useCallback(async () => {
    setError(null);
    try {
      const selected = await openFilePicker({
        multiple: false,
        filters: [{ name: "rclone config", extensions: ["conf"] }],
      });
      if (!selected) return;

      const filePath = typeof selected === "string" ? selected : selected;
      const content = await invoke<string>("read_text_file", {
        path: filePath,
      });

      const parsed = parseRcloneConf(content);
      if (parsed.length === 0) {
        setError("No remotes found in the selected file.");
        return;
      }

      const existingNames = new Set((existingRemotes ?? []).map((r) => r.name));

      setRows(
        parsed.map((p) => ({
          parsed: p,
          selected: true,
          rename: "",
          hasConflict: existingNames.has(p.name),
        })),
      );
      setStep("review");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, [existingRemotes]);

  const toggleSelected = useCallback((index: number) => {
    setRows((prev) =>
      prev.map((row, i) =>
        i === index ? { ...row, selected: !row.selected } : row,
      ),
    );
  }, []);

  const setRename = useCallback((index: number, value: string) => {
    setRows((prev) =>
      prev.map((row, i) => (i === index ? { ...row, rename: value } : row)),
    );
  }, []);

  const handleImport = useCallback(async () => {
    const toImport = rows.filter((r) => r.selected);
    if (toImport.length === 0) {
      setError("Select at least one remote to import.");
      return;
    }

    // Validate names
    const names = new Set<string>();
    for (const row of toImport) {
      const name = row.rename.trim() || row.parsed.name;
      if (!name) {
        setError("All selected remotes must have a name.");
        return;
      }
      if (names.has(name)) {
        setError(
          `Duplicate name: "${name}". Please rename conflicting remotes.`,
        );
        return;
      }
      names.add(name);
    }

    setStep("importing");
    setError(null);
    setImportErrors([]);

    const errs: string[] = [];
    for (const row of toImport) {
      const name = row.rename.trim() || row.parsed.name;
      try {
        await createRemote(name, row.parsed.type, row.parsed.parameters);
      } catch (err) {
        errs.push(
          `${name}: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    setImportErrors(errs);
    queryClient.invalidateQueries({ queryKey: ["remotes"] });

    if (errs.length === 0) {
      handleClose();
    } else {
      setStep("review");
    }
  }, [rows, queryClient, handleClose]);

  const selectedCount = rows.filter((r) => r.selected).length;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && handleClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Import rclone Config</DialogTitle>
          <DialogDescription>
            {step === "idle" || step === "importing"
              ? "Select an rclone .conf file to import remotes from."
              : `Found ${rows.length} remote${rows.length === 1 ? "" : "s"}. Choose which ones to import.`}
          </DialogDescription>
        </DialogHeader>

        {(step === "idle" || step === "importing") && (
          <div className="flex flex-col items-center gap-4 py-6">
            <Button
              variant="outline"
              onClick={handlePickFile}
              disabled={step === "importing"}
            >
              {step === "importing" && (
                <Loader2
                  className="size-4 animate-spin"
                  data-icon="inline-start"
                />
              )}
              Choose File…
            </Button>
          </div>
        )}

        {step === "review" && (
          <ScrollArea className="max-h-80">
            <div className="flex flex-col gap-3 pr-2">
              {rows.map((row, i) => {
                const effectiveName = row.rename.trim() || row.parsed.name;
                const nameConflict = row.hasConflict && !row.rename.trim();
                return (
                  <div
                    key={row.parsed.name}
                    className="flex flex-col gap-1.5 rounded-lg border p-3"
                  >
                    <div className="flex items-center gap-3">
                      <input
                        type="checkbox"
                        id={`remote-${i}`}
                        checked={row.selected}
                        onChange={() => toggleSelected(i)}
                        className="size-4 shrink-0 accent-primary"
                      />
                      <Label
                        htmlFor={`remote-${i}`}
                        className="flex-1 cursor-pointer"
                      >
                        <span className="font-medium">{row.parsed.name}</span>
                        <span className="text-muted-foreground ml-2 text-xs">
                          {row.parsed.type}
                        </span>
                      </Label>
                      {row.hasConflict && (
                        <span className="text-destructive text-xs font-medium">
                          conflict
                        </span>
                      )}
                    </div>

                    {row.selected && row.hasConflict && (
                      <div className="ml-7 flex flex-col gap-1">
                        <Label
                          htmlFor={`rename-${i}`}
                          className="text-xs text-muted-foreground"
                        >
                          Rename to avoid conflict
                        </Label>
                        <Input
                          id={`rename-${i}`}
                          value={row.rename}
                          onChange={(e) => setRename(i, e.target.value)}
                          placeholder={`${row.parsed.name}-imported`}
                          className={nameConflict ? "border-destructive" : ""}
                        />
                        {nameConflict && (
                          <p className="text-xs text-destructive">
                            "{effectiveName}" already exists — enter a new name.
                          </p>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </ScrollArea>
        )}

        {importErrors.length > 0 && (
          <div className="rounded-md border border-destructive/50 bg-destructive/10 p-3">
            <p className="text-sm font-medium text-destructive mb-1">
              Some remotes failed to import:
            </p>
            <ul className="text-xs text-destructive space-y-0.5">
              {importErrors.map((e) => (
                <li key={e}>• {e}</li>
              ))}
            </ul>
          </div>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        {step === "review" && (
          <DialogFooter>
            <Button variant="outline" onClick={handlePickFile}>
              Choose Different File
            </Button>
            <Button onClick={handleImport} disabled={selectedCount === 0}>
              Import {selectedCount > 0 ? `${selectedCount} ` : ""}
              {selectedCount === 1 ? "Remote" : "Remotes"}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
