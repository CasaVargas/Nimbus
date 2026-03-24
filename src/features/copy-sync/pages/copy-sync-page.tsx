import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowRight, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/page-header";
import { PathPicker } from "../components/path-picker";
import { useCopySync } from "../hooks/use-sync";

export default function CopySyncPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const initialSrc = searchParams.get("src") ?? "";
  const [srcRemote, srcPath] = parseFs(initialSrc);

  const [operation, setOperation] = useState<"copy" | "sync">("copy");
  const [sourceRemote, setSourceRemote] = useState(srcRemote);
  const [sourcePath, setSourcePath] = useState(srcPath);
  const [destRemote, setDestRemote] = useState("");
  const [destPath, setDestPath] = useState("");
  const [dryRun, setDryRun] = useState(false);

  const copySync = useCopySync();

  const srcFs = sourceRemote
    ? `${sourceRemote}:${sourcePath}`
    : "";
  const dstFs = destRemote
    ? `${destRemote}:${destPath}`
    : "";
  const canStart = srcFs !== "" && dstFs !== "";

  function handleStart() {
    copySync.mutate(
      { operation, srcFs, dstFs, dryRun },
      {
        onSuccess: () => {
          if (dryRun) {
            toast.success("Dry run complete - no files were changed");
          } else {
            toast.success(
              `${operation === "copy" ? "Copy" : "Sync"} started`,
            );
            navigate("/transfers");
          }
        },
        onError: (err) => {
          toast.error(`Failed to start ${operation}: ${err.message}`);
        },
      },
    );
  }

  return (
    <div>
      <PageHeader
        title="Copy / Sync"
        description="Copy or sync files between remotes"
      />
      <div className="mx-auto max-w-2xl space-y-6 p-6">
        {/* Operation Toggle */}
        <div className="flex gap-2">
          <Button
            variant={operation === "copy" ? "default" : "outline"}
            onClick={() => setOperation("copy")}
          >
            Copy
          </Button>
          <Button
            variant={operation === "sync" ? "default" : "outline"}
            onClick={() => setOperation("sync")}
          >
            Sync
          </Button>
        </div>

        {/* Source / Destination */}
        <div className="flex items-end gap-4">
          <div className="flex-1">
            <PathPicker
              label="Source"
              remote={sourceRemote}
              path={sourcePath}
              onRemoteChange={setSourceRemote}
              onPathChange={setSourcePath}
            />
          </div>
          <ArrowRight className="mb-2 h-5 w-5 shrink-0 text-muted-foreground" />
          <div className="flex-1">
            <PathPicker
              label="Destination"
              remote={destRemote}
              path={destPath}
              onRemoteChange={setDestRemote}
              onPathChange={setDestPath}
            />
          </div>
        </div>

        {/* Sync Warning */}
        {operation === "sync" && (
          <div className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-600 dark:text-amber-400">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <span>
              Sync will delete files in the destination that don't exist in the
              source.
            </span>
          </div>
        )}

        {/* Options */}
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={dryRun}
            onChange={(e) => setDryRun(e.target.checked)}
            className="rounded border-input"
          />
          Dry run (preview changes without modifying files)
        </label>

        {/* Start */}
        <Button
          className="w-full"
          disabled={!canStart || copySync.isPending}
          onClick={handleStart}
        >
          {copySync.isPending
            ? "Starting..."
            : `Start ${operation === "copy" ? "Copy" : "Sync"}`}
        </Button>
      </div>
    </div>
  );
}

/** Parse "remote:path" into [remote, path] */
function parseFs(fs: string): [string, string] {
  const idx = fs.indexOf(":");
  if (idx === -1) return ["", fs];
  return [fs.slice(0, idx), fs.slice(idx + 1)];
}
