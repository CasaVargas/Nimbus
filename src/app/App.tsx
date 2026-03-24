import { Outlet } from "react-router-dom";
import { Providers } from "./providers";
import { Sidebar } from "@/components/sidebar";
import { Toaster } from "sonner";

export default function App() {
  return (
    <Providers>
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
        <Toaster />
      </div>
    </Providers>
  );
}
