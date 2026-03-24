import { Outlet } from "react-router-dom";
import { Toaster } from "sonner";
import { ConnectionBanner } from "@/components/connection-banner";
import { Sidebar } from "@/components/sidebar";
import { useAutoMount } from "@/hooks/use-auto-mount";
import { useDaemon } from "../hooks/use-daemon";
import { Providers } from "./providers";

export default function App() {
  const { status, error, retry } = useDaemon();
  useAutoMount(status === "connected");

  return (
    <Providers>
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex-1 flex flex-col overflow-hidden">
          <ConnectionBanner status={status} error={error} onRetry={retry} />
          <main className="flex-1 overflow-auto">
            <Outlet />
          </main>
        </div>
      </div>
      <Toaster />
    </Providers>
  );
}
