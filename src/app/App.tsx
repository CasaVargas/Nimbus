import { Outlet } from "react-router-dom";
import { Providers } from "./providers";
import { Sidebar } from "@/components/sidebar";
import { ConnectionBanner } from "@/components/connection-banner";
import { Toaster } from "sonner";
import { useDaemon } from "../hooks/use-daemon";

export default function App() {
  const { status, error, retry } = useDaemon();

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
