import { AlertCircle, Loader2, RefreshCw } from "lucide-react";

interface ConnectionBannerProps {
  status: "connecting" | "connected" | "error";
  error: string | null;
  onRetry: () => void;
}

export function ConnectionBanner({
  status,
  error,
  onRetry,
}: ConnectionBannerProps) {
  if (status === "connected") return null;

  return (
    <div
      className={`flex items-center gap-2 px-4 py-2 text-sm ${
        status === "connecting"
          ? "bg-yellow-500/10 text-yellow-600 dark:text-yellow-400"
          : "bg-destructive/10 text-destructive"
      }`}
    >
      {status === "connecting" ? (
        <>
          <Loader2 size={14} className="animate-spin" />
          <span>Connecting to rclone daemon...</span>
        </>
      ) : (
        <>
          <AlertCircle size={14} />
          <span>{error ?? "Failed to connect"}</span>
          <button
            onClick={onRetry}
            className="ml-auto flex items-center gap-1 hover:underline"
          >
            <RefreshCw size={12} /> Retry
          </button>
        </>
      )}
    </div>
  );
}
