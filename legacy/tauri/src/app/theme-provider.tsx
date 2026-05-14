import { useEffect } from "react";
import { type Theme, useAppStore } from "@/stores/app-store";

function applyTheme(theme: Theme) {
  const root = document.documentElement;
  if (theme === "system") {
    const prefersDark = window.matchMedia(
      "(prefers-color-scheme: dark)",
    ).matches;
    root.classList.toggle("dark", prefersDark);
  } else {
    root.classList.toggle("dark", theme === "dark");
  }
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useAppStore((s) => s.theme);

  useEffect(() => {
    applyTheme(theme);

    if (theme === "system") {
      const mq = window.matchMedia("(prefers-color-scheme: dark)");
      const handler = () => applyTheme("system");
      mq.addEventListener("change", handler);
      return () => mq.removeEventListener("change", handler);
    }
  }, [theme]);

  return <>{children}</>;
}
