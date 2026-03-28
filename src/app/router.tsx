import { createBrowserRouter } from "react-router-dom";
import BrowserPage from "@/features/browser/pages/browser-page";
import CopySyncPage from "@/features/copy-sync/pages/copy-sync-page";
import MountPage from "@/features/mount/pages/mount-page";
import OnboardingPage from "@/features/onboarding/pages/onboarding-page";
import RemotesPage from "@/features/remotes/pages/remotes-page";
import SettingsPage from "@/features/settings/pages/settings-page";
import TransfersPage from "@/features/transfers/pages/transfers-page";
import App from "./App";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <App />,
    children: [
      { index: true, element: <RemotesPage /> },
      { path: "onboarding", element: <OnboardingPage /> },
      { path: "browser/:remote?/*", element: <BrowserPage /> },
      { path: "copy-sync", element: <CopySyncPage /> },
      { path: "transfers", element: <TransfersPage /> },
      { path: "mounts", element: <MountPage /> },
      { path: "settings", element: <SettingsPage /> },
    ],
  },
]);
