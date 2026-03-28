import { Outlet } from "react-router-dom";
import { Toaster } from "sonner";
import { ConnectionBanner } from "@/components/connection-banner";
import { Sidebar } from "@/components/sidebar";
import { useAutoMount } from "@/hooks/use-auto-mount";
import { useFileProviderSync } from "@/hooks/use-file-provider-sync";
import { useKeyboardShortcuts } from "@/hooks/use-keyboard-shortcuts";
import { useRemotes } from "@/features/remotes/hooks/use-remotes";
import { useDaemon } from "../hooks/use-daemon";
import { Providers } from "./providers";

function AppShell() {
  const { status, error, retry } = useDaemon();
  useAutoMount(status === "connected");

  // Sync File Provider shared state when daemon connects
  const { data: remotesList } = useRemotes();
  const remoteNames = remotesList?.map((r) => r.name) ?? [];
  useFileProviderSync(status === "connected", remoteNames);
  useKeyboardShortcuts();

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <ConnectionBanner status={status} error={error} onRetry={retry} />
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <Providers>
      <AppShell />
      <Toaster />
    </Providers>
  );
}
