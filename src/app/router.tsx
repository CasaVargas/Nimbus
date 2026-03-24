import { createBrowserRouter } from "react-router-dom";
import App from "./App";
import RemotesPage from "@/features/remotes/pages/remotes-page";
import BrowserPage from "@/features/browser/pages/browser-page";
import CopySyncPage from "@/features/copy-sync/pages/copy-sync-page";
import TransfersPage from "@/features/transfers/pages/transfers-page";
import MountPage from "@/features/mount/pages/mount-page";
import SettingsPage from "@/features/settings/pages/settings-page";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <App />,
    children: [
      { index: true, element: <RemotesPage /> },
      { path: "browser/:remote?/*", element: <BrowserPage /> },
      { path: "copy-sync", element: <CopySyncPage /> },
      { path: "transfers", element: <TransfersPage /> },
      { path: "mounts", element: <MountPage /> },
      { path: "settings", element: <SettingsPage /> },
    ],
  },
]);
