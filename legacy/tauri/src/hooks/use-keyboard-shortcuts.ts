import { useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";

const NAV_SHORTCUTS: Record<string, string> = {
  "1": "/",
  "2": "/browser",
  "3": "/copy-sync",
  "4": "/transfers",
  "5": "/mounts",
  "6": "/settings",
  ",": "/settings",
};

/**
 * Global keyboard shortcuts for the app.
 * Cmd+1-6 navigates between pages, Cmd+, opens settings.
 */
export function useKeyboardShortcuts() {
  const navigate = useNavigate();
  const location = useLocation();

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      // Only handle Cmd/Ctrl shortcuts
      if (!e.metaKey && !e.ctrlKey) return;

      // Don't intercept when typing in inputs
      const target = e.target as HTMLElement;
      if (
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.isContentEditable
      ) {
        return;
      }

      // Navigation shortcuts: Cmd+1-6, Cmd+,
      const navTarget = NAV_SHORTCUTS[e.key];
      if (navTarget) {
        e.preventDefault();
        if (location.pathname !== navTarget) {
          navigate(navTarget);
        }
        return;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate, location.pathname]);
}
