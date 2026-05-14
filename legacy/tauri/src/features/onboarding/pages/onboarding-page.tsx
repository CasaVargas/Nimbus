import { CheckCircle2, Cloud, Loader2, XCircle } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { useAppStore } from "@/stores/app-store";
import { useDaemon } from "@/hooks/use-daemon";
import { AddRemoteDialog } from "@/features/remotes/components/add-remote-dialog";
import { useRemotes } from "@/features/remotes/hooks/use-remotes";

export default function OnboardingPage() {
  const navigate = useNavigate();
  const { status } = useDaemon();
  const { data: remotes } = useRemotes();
  const setOnboarded = useAppStore((s) => s.setOnboarded);
  const [showAddRemote, setShowAddRemote] = useState(false);

  const daemonReady = status === "connected";
  const hasRemotes = (remotes?.length ?? 0) > 0;

  const handleFinish = useCallback(() => {
    setOnboarded(true);
    navigate("/");
  }, [setOnboarded, navigate]);

  // Auto-mark onboarded if user already has remotes
  useEffect(() => {
    if (daemonReady && hasRemotes) {
      setOnboarded(true);
    }
  }, [daemonReady, hasRemotes, setOnboarded]);

  return (
    <div className="flex h-full items-center justify-center">
      <div className="mx-auto max-w-md space-y-8 p-6 text-center">
        <div className="space-y-2">
          <Cloud className="mx-auto size-12 text-primary" />
          <h1 className="text-2xl font-bold">Welcome to Nimbus</h1>
          <p className="text-muted-foreground">
            Your cloud, one app. Let's get you connected.
          </p>
        </div>

        <div className="space-y-4 text-left">
          {/* Step 1: Daemon check */}
          <div className="flex items-center gap-3 rounded-lg border p-4">
            {daemonReady ? (
              <CheckCircle2 className="size-5 shrink-0 text-green-500" />
            ) : (
              <Loader2 className="size-5 shrink-0 animate-spin text-muted-foreground" />
            )}
            <div>
              <p className="text-sm font-medium">
                {daemonReady ? "rclone daemon connected" : "Connecting to rclone..."}
              </p>
              <p className="text-xs text-muted-foreground">
                {daemonReady
                  ? "Ready to manage your cloud storage"
                  : "Starting the rclone daemon in the background"}
              </p>
            </div>
          </div>

          {/* Step 2: Add first remote */}
          <div className="flex items-center gap-3 rounded-lg border p-4">
            {hasRemotes ? (
              <CheckCircle2 className="size-5 shrink-0 text-green-500" />
            ) : daemonReady ? (
              <XCircle className="size-5 shrink-0 text-muted-foreground" />
            ) : (
              <div className="size-5 shrink-0" />
            )}
            <div className="flex-1">
              <p className="text-sm font-medium">
                {hasRemotes
                  ? `${remotes!.length} remote${remotes!.length > 1 ? "s" : ""} configured`
                  : "Add your first remote"}
              </p>
              <p className="text-xs text-muted-foreground">
                {hasRemotes
                  ? "You're all set to browse, sync, and mount"
                  : "Connect to Google Drive, S3, Dropbox, and 40+ more"}
              </p>
            </div>
            {!hasRemotes && daemonReady && (
              <Button size="sm" onClick={() => setShowAddRemote(true)}>
                Add Remote
              </Button>
            )}
          </div>
        </div>

        <Button
          className="w-full"
          size="lg"
          onClick={handleFinish}
          disabled={!daemonReady}
        >
          {hasRemotes ? "Get Started" : "Skip for Now"}
        </Button>
      </div>

      <AddRemoteDialog
        open={showAddRemote}
        onClose={() => setShowAddRemote(false)}
      />
    </div>
  );
}
