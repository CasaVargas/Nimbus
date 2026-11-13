# StreamCloned v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-platform desktop GUI for rclone with file browsing, copy/sync, mount management, and transfer tracking.

**Architecture:** Tauri v2 shell with React 19 + TypeScript frontend. "Thin Rust, Fat TypeScript" — Rust handles only process management, system tray, and mounts. All business logic and rclone API communication lives in TypeScript via HTTP to the rclone daemon.

**Tech Stack:** Tauri v2, React 19, TypeScript 5.x, Vite 6, Tailwind CSS v4, shadcn/ui, Zustand, TanStack Query v5, React Router v7, Biome, Lucide React

**Spec:** `docs/superpowers/specs/2026-03-23-streamcloned-design.md`

---

## File Map

### Rust Backend (`src-tauri/`)

| File | Responsibility |
|------|---------------|
| `src-tauri/src/main.rs` | Tauri entry point |
| `src-tauri/src/lib.rs` | Plugin registration, command registration |
| `src-tauri/src/commands/rclone.rs` | Spawn/stop rclone daemon, port detection, health check |
| `src-tauri/src/commands/mod.rs` | Re-export commands |
| `src-tauri/Cargo.toml` | Rust dependencies |
| `src-tauri/tauri.conf.json` | Tauri config (windows, bundle, plugins, permissions) |
| `src-tauri/capabilities/default.json` | Tauri v2 capability permissions |

### Frontend Core (`src/`)

| File | Responsibility |
|------|---------------|
| `src/main.tsx` | React entry point, render root |
| `src/app/App.tsx` | App shell with sidebar layout + router outlet |
| `src/app/router.tsx` | Route definitions for all pages |
| `src/app/providers.tsx` | QueryClientProvider, ThemeProvider wrappers |
| `src/app/theme-provider.tsx` | Dark/light/system theme context |
| `src/index.css` | Tailwind directives + CSS custom properties |

### Rclone API Layer (`src/lib/rclone/`)

| File | Responsibility |
|------|---------------|
| `src/lib/rclone/client.ts` | HTTP client for rclone RC API (POST JSON, error handling) |
| `src/lib/rclone/types.ts` | TypeScript interfaces for all rclone API responses |
| `src/lib/rclone/remotes.ts` | Remote CRUD operations (list, create, update, delete, providers) |
| `src/lib/rclone/operations.ts` | File operations (list, stat, mkdir, delete, copy, move, purge) |
| `src/lib/rclone/sync.ts` | Copy & sync tree operations (async jobs) |
| `src/lib/rclone/jobs.ts` | Job tracking (list, status, stop) |
| `src/lib/rclone/mount.ts` | Mount/unmount/list mounts |
| `src/lib/rclone/stats.ts` | Core stats, bandwidth limit |

### Tauri IPC Wrappers (`src/lib/tauri/`)

| File | Responsibility |
|------|---------------|
| `src/lib/tauri/rclone.ts` | Invoke Rust commands: start/stop daemon, get port |
| `src/lib/tauri/events.ts` | Listen for Tauri events (tray actions, daemon status) |

### Zustand Stores (`src/stores/`)

| File | Responsibility |
|------|---------------|
| `src/stores/app-store.ts` | Theme, sidebar state, rclone settings (port, binary path, bandwidth) |
| `src/stores/transfer-store.ts` | Transfer history (active/completed/failed), persisted |
| `src/stores/mount-store.ts` | Mount configs, auto-mount list, persisted |

### Shared Components (`src/components/`)

| File | Responsibility |
|------|---------------|
| `src/components/ui/` | shadcn/ui components (button, card, dialog, toast, etc.) |
| `src/components/sidebar.tsx` | App sidebar navigation |
| `src/components/page-header.tsx` | Consistent page title + actions bar |
| `src/components/remote-icon.tsx` | Cloud provider icon by type string |
| `src/components/path-breadcrumb.tsx` | Clickable breadcrumb for remote paths |
| `src/components/connection-banner.tsx` | "Reconnecting..." daemon status banner |
| `src/components/empty-state.tsx` | Reusable empty state with icon + CTA |

### Feature: Remotes (`src/features/remotes/`)

| File | Responsibility |
|------|---------------|
| `src/features/remotes/pages/remotes-page.tsx` | Home screen — grid of remote cards |
| `src/features/remotes/components/remote-card.tsx` | Single remote card with actions |
| `src/features/remotes/components/add-remote-dialog.tsx` | Provider picker + config form wizard |
| `src/features/remotes/components/provider-picker.tsx` | Grid of provider icons with search |
| `src/features/remotes/components/config-form.tsx` | Dynamic form from provider Options schema |
| `src/features/remotes/components/delete-remote-dialog.tsx` | Confirmation dialog |
| `src/features/remotes/hooks/use-remotes.ts` | TanStack Query hooks for remote CRUD |
| `src/features/remotes/hooks/use-providers.ts` | TanStack Query hook for provider list |

### Feature: File Browser (`src/features/browser/`)

| File | Responsibility |
|------|---------------|
| `src/features/browser/pages/browser-page.tsx` | File browser page with toolbar + listing |
| `src/features/browser/components/file-list.tsx` | List view of files |
| `src/features/browser/components/file-grid.tsx` | Grid view of files |
| `src/features/browser/components/file-row.tsx` | Single file row (list mode) |
| `src/features/browser/components/file-card.tsx` | Single file card (grid mode) |
| `src/features/browser/components/browser-toolbar.tsx` | View toggle, new folder, upload, filter, sort |
| `src/features/browser/components/file-context-menu.tsx` | Right-click menu (rename, delete, download) |
| `src/features/browser/components/create-folder-dialog.tsx` | New folder inline creation |
| `src/features/browser/hooks/use-file-list.ts` | TanStack Query hook for directory listing |
| `src/features/browser/hooks/use-file-operations.ts` | Mutation hooks for file CRUD |
| `src/features/browser/hooks/use-selection.ts` | Multi-select state (click, shift, ctrl) |

### Feature: Copy & Sync (`src/features/copy-sync/`)

| File | Responsibility |
|------|---------------|
| `src/features/copy-sync/pages/copy-sync-page.tsx` | Source → Dest picker with options |
| `src/features/copy-sync/components/path-picker.tsx` | Remote + path selector with browse button |
| `src/features/copy-sync/components/sync-options.tsx` | Filters, dry run toggle, bandwidth |
| `src/features/copy-sync/components/dry-run-preview.tsx` | Preview of what would change |
| `src/features/copy-sync/hooks/use-sync.ts` | Mutation hooks for copy/sync operations |

### Feature: Transfers (`src/features/transfers/`)

| File | Responsibility |
|------|---------------|
| `src/features/transfers/pages/transfers-page.tsx` | Transfer queue with tabs (active/completed) |
| `src/features/transfers/components/transfer-item.tsx` | Single transfer row with progress |
| `src/features/transfers/components/transfer-progress.tsx` | Progress bar + speed + ETA |
| `src/features/transfers/hooks/use-transfers.ts` | Polling hook for job status + stats |

### Feature: Mounts (`src/features/mount/`)

| File | Responsibility |
|------|---------------|
| `src/features/mount/pages/mount-page.tsx` | Mount list with add/remove |
| `src/features/mount/components/mount-item.tsx` | Single mount row with toggle |
| `src/features/mount/components/add-mount-dialog.tsx` | Remote + mount point picker |
| `src/features/mount/hooks/use-mounts.ts` | TanStack Query hooks for mount operations |

### Feature: Settings (`src/features/settings/`)

| File | Responsibility |
|------|---------------|
| `src/features/settings/pages/settings-page.tsx` | Settings form with sections |
| `src/features/settings/components/appearance-section.tsx` | Theme picker |
| `src/features/settings/components/rclone-section.tsx` | Binary path, port, autostart |
| `src/features/settings/components/transfer-section.tsx` | Concurrent transfers, bandwidth |
| `src/features/settings/components/about-section.tsx` | Version info, links |

### Feature: Onboarding (`src/features/onboarding/`)

| File | Responsibility |
|------|---------------|
| `src/features/onboarding/pages/onboarding-page.tsx` | Welcome screen + setup wizard |
| `src/features/onboarding/components/daemon-status.tsx` | Connection status indicator |

### Tests (`src/__tests__/`)

| File | Responsibility |
|------|---------------|
| `src/__tests__/lib/rclone/client.test.ts` | Rclone HTTP client unit tests |
| `src/__tests__/lib/rclone/remotes.test.ts` | Remote API function tests |
| `src/__tests__/lib/rclone/operations.test.ts` | File operation API tests |
| `src/__tests__/lib/rclone/sync.test.ts` | Sync/copy API tests |
| `src/__tests__/stores/app-store.test.ts` | App store tests |
| `src/__tests__/stores/transfer-store.test.ts` | Transfer store tests |
| `src/__tests__/stores/mount-store.test.ts` | Mount store tests |

---

## Task 1: Project Scaffolding

**Goal:** Create the Tauri v2 + React + TypeScript project with all dependencies installed and a dev server that compiles and opens a window.

**Files:**
- Create: All root config files, `src-tauri/` skeleton, `src/main.tsx`, `src/app/App.tsx`

- [ ] **Step 1: Create Tauri v2 project**

```bash
cd StreamCloned
npm create tauri-app@latest -- --template react-ts --name streamcloned --identifier com.streamcloned.app --directory .
```

If the CLI prompts interactively instead of accepting flags, run `npm create tauri-app@latest` and select: React, TypeScript, npm. Then move the generated files into the current directory if needed.

- [ ] **Step 2: Verify the scaffolded project compiles**

```bash
cd StreamCloned
npm install
npm run tauri dev
```

Expected: A Tauri window opens with the default React template. Close it after verifying.

- [ ] **Step 3: Install frontend dependencies**

```bash
npm install zustand @tanstack/react-query @tanstack/react-query-devtools react-router-dom lucide-react
npm install -D tailwindcss @tailwindcss/vite @biomejs/biome
```

- [ ] **Step 4: Install Tauri plugin npm packages**

```bash
npm install @tauri-apps/api @tauri-apps/plugin-shell @tauri-apps/plugin-dialog @tauri-apps/plugin-store @tauri-apps/plugin-http @tauri-apps/plugin-notification @tauri-apps/plugin-opener
```

- [ ] **Step 5: Add Tauri Rust plugins**

```bash
cd src-tauri
cargo add tauri-plugin-shell tauri-plugin-dialog tauri-plugin-store tauri-plugin-http tauri-plugin-notification tauri-plugin-opener
cd ..
```

- [ ] **Step 6: Configure Biome**

Create `biome.json`:

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0/schema.json",
  "organizeImports": {
    "enabled": true
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

- [ ] **Step 7: Configure Tailwind CSS v4**

Update `vite.config.ts` to include the Tailwind plugin:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig(async () => ({
  plugins: [react(), tailwindcss()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host ? { protocol: "ws", host, port: 1421 } : undefined,
    watch: { ignored: ["**/src-tauri/**"] },
  },
}));
```

Replace `src/index.css` (or the main CSS file) with:

```css
@import "tailwindcss";

:root {
  --background: 0 0% 100%;
  --foreground: 0 0% 3.9%;
  --card: 0 0% 100%;
  --card-foreground: 0 0% 3.9%;
  --popover: 0 0% 100%;
  --popover-foreground: 0 0% 3.9%;
  --primary: 0 0% 9%;
  --primary-foreground: 0 0% 98%;
  --secondary: 0 0% 96.1%;
  --secondary-foreground: 0 0% 9%;
  --muted: 0 0% 96.1%;
  --muted-foreground: 0 0% 45.1%;
  --accent: 0 0% 96.1%;
  --accent-foreground: 0 0% 9%;
  --destructive: 0 84.2% 60.2%;
  --destructive-foreground: 0 0% 98%;
  --border: 0 0% 89.8%;
  --input: 0 0% 89.8%;
  --ring: 0 0% 3.9%;
  --radius: 0.5rem;
  --sidebar-background: 0 0% 98%;
  --sidebar-foreground: 240 5.3% 26.1%;
  --sidebar-primary: 240 5.9% 10%;
  --sidebar-primary-foreground: 0 0% 98%;
  --sidebar-accent: 240 4.8% 95.9%;
  --sidebar-accent-foreground: 240 5.9% 10%;
  --sidebar-border: 220 13% 91%;
  --sidebar-ring: 217.2 91.2% 59.8%;
}

.dark {
  --background: 0 0% 3.9%;
  --foreground: 0 0% 98%;
  --card: 0 0% 3.9%;
  --card-foreground: 0 0% 98%;
  --popover: 0 0% 3.9%;
  --popover-foreground: 0 0% 98%;
  --primary: 0 0% 98%;
  --primary-foreground: 0 0% 9%;
  --secondary: 0 0% 14.9%;
  --secondary-foreground: 0 0% 98%;
  --muted: 0 0% 14.9%;
  --muted-foreground: 0 0% 63.9%;
  --accent: 0 0% 14.9%;
  --accent-foreground: 0 0% 98%;
  --destructive: 0 62.8% 30.6%;
  --destructive-foreground: 0 0% 98%;
  --border: 0 0% 14.9%;
  --input: 0 0% 14.9%;
  --ring: 0 0% 83.1%;
  --sidebar-background: 240 5.9% 10%;
  --sidebar-foreground: 240 4.8% 95.9%;
  --sidebar-primary: 224.3 76.3% 48%;
  --sidebar-primary-foreground: 0 0% 100%;
  --sidebar-accent: 240 3.7% 15.9%;
  --sidebar-accent-foreground: 240 4.8% 95.9%;
  --sidebar-border: 240 3.7% 15.9%;
  --sidebar-ring: 217.2 91.2% 59.8%;
}

body {
  font-family: system-ui, -apple-system, sans-serif;
  background-color: hsl(var(--background));
  color: hsl(var(--foreground));
}
```

- [ ] **Step 8: Initialize shadcn/ui**

```bash
npx shadcn@latest init
```

When prompted: style=new-york, base-color=zinc, css-variables=yes. This creates `components.json` and sets up the `src/components/ui/` directory.

Then add the core components we'll need:

```bash
npx shadcn@latest add button card dialog dropdown-menu input label scroll-area separator sheet tabs toast toaster tooltip badge progress select
```

- [ ] **Step 9: Register Tauri plugins in lib.rs**

Replace `src-tauri/src/lib.rs` with:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 10: Update tauri.conf.json**

Update `src-tauri/tauri.conf.json`:

```json
{
  "productName": "StreamCloned",
  "version": "0.1.0",
  "identifier": "com.streamcloned.app",
  "build": {
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build",
    "devUrl": "http://localhost:1420",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "title": "StreamCloned",
        "width": 1200,
        "height": 800,
        "minWidth": 800,
        "minHeight": 600,
        "resizable": true,
        "decorations": true
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ]
  },
  "plugins": {}
}
```

- [ ] **Step 11: Set up Tauri v2 capabilities/permissions**

Create `src-tauri/capabilities/default.json`:

```json
{
  "identifier": "default",
  "description": "Default permissions for StreamCloned",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "shell:allow-execute",
    "shell:allow-open",
    "dialog:allow-open",
    "dialog:allow-save",
    "dialog:allow-message",
    "dialog:allow-ask",
    "store:default",
    "http:default",
    "notification:default",
    "opener:default"
  ]
}
```

- [ ] **Step 12: Verify everything compiles**

```bash
npm run tauri dev
```

Expected: Tauri window opens with the React app rendering. Tailwind styles work. Close it.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat: scaffold Tauri v2 + React 19 + TypeScript project

Includes: Tailwind CSS v4, shadcn/ui, Zustand, TanStack Query,
React Router, Biome, Lucide React. All Tauri plugins registered."
```

---

## Task 2: App Shell, Routing & Theme

**Goal:** Build the sidebar layout, routing between pages, and light/dark theme toggle. After this task, you can navigate between stub pages.

**Files:**
- Create: `src/app/App.tsx`, `src/app/router.tsx`, `src/app/providers.tsx`, `src/app/theme-provider.tsx`
- Create: `src/components/sidebar.tsx`, `src/components/page-header.tsx`
- Create: Stub pages for all features
- Create: `src/stores/app-store.ts`
- Test: `src/__tests__/stores/app-store.test.ts`

- [ ] **Step 1: Write app store test**

Create `src/__tests__/stores/app-store.test.ts`:

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { useAppStore } from "../../stores/app-store";

describe("appStore", () => {
  beforeEach(() => {
    useAppStore.setState({
      theme: "system",
      sidebarCollapsed: false,
      rclonePort: 5572,
      rcloneBinaryPath: "",
      bandwidthLimit: "",
      concurrentTransfers: 4,
    });
  });

  it("has correct default values", () => {
    const state = useAppStore.getState();
    expect(state.theme).toBe("system");
    expect(state.sidebarCollapsed).toBe(false);
    expect(state.rclonePort).toBe(5572);
    expect(state.concurrentTransfers).toBe(4);
  });

  it("sets theme", () => {
    useAppStore.getState().setTheme("dark");
    expect(useAppStore.getState().theme).toBe("dark");
  });

  it("toggles sidebar", () => {
    useAppStore.getState().toggleSidebar();
    expect(useAppStore.getState().sidebarCollapsed).toBe(true);
    useAppStore.getState().toggleSidebar();
    expect(useAppStore.getState().sidebarCollapsed).toBe(false);
  });

  it("sets rclone port", () => {
    useAppStore.getState().setRclonePort(5573);
    expect(useAppStore.getState().rclonePort).toBe(5573);
  });
});
```

- [ ] **Step 2: Install vitest and run test to verify it fails**

```bash
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
```

Add to `vite.config.ts` (or create `vitest.config.ts`):

```ts
// Add to the existing vite.config.ts defineConfig:
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: [],
  },
```

Add test script to `package.json`:

```json
"scripts": {
  "test": "vitest run",
  "test:watch": "vitest"
}
```

Run: `npm test -- src/__tests__/stores/app-store.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement app store**

Create `src/stores/app-store.ts`:

```ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

export type Theme = "light" | "dark" | "system";

interface AppState {
  theme: Theme;
  sidebarCollapsed: boolean;
  rclonePort: number;
  rcloneBinaryPath: string;
  bandwidthLimit: string;
  concurrentTransfers: number;

  setTheme: (theme: Theme) => void;
  toggleSidebar: () => void;
  setRclonePort: (port: number) => void;
  setRcloneBinaryPath: (path: string) => void;
  setBandwidthLimit: (limit: string) => void;
  setConcurrentTransfers: (count: number) => void;
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      theme: "system",
      sidebarCollapsed: false,
      rclonePort: 5572,
      rcloneBinaryPath: "",
      bandwidthLimit: "",
      concurrentTransfers: 4,

      setTheme: (theme) => set({ theme }),
      toggleSidebar: () =>
        set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),
      setRclonePort: (port) => set({ rclonePort: port }),
      setRcloneBinaryPath: (path) => set({ rcloneBinaryPath: path }),
      setBandwidthLimit: (limit) => set({ bandwidthLimit: limit }),
      setConcurrentTransfers: (count) => set({ concurrentTransfers: count }),
    }),
    { name: "streamcloned-app" }
  )
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/__tests__/stores/app-store.test.ts`
Expected: PASS

- [ ] **Step 5: Create theme provider**

Create `src/app/theme-provider.tsx`:

```tsx
import { createContext, useContext, useEffect } from "react";
import { useAppStore, type Theme } from "../stores/app-store";

const ThemeContext = createContext<{
  theme: Theme;
  setTheme: (theme: Theme) => void;
}>({ theme: "system", setTheme: () => {} });

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useAppStore((s) => s.theme);
  const setTheme = useAppStore((s) => s.setTheme);

  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove("light", "dark");

    if (theme === "system") {
      const systemTheme = window.matchMedia("(prefers-color-scheme: dark)")
        .matches
        ? "dark"
        : "light";
      root.classList.add(systemTheme);
    } else {
      root.classList.add(theme);
    }
  }, [theme]);

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
```

- [ ] **Step 6: Create providers wrapper**

Create `src/app/providers.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "./theme-provider";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
      staleTime: 30_000,
    },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>{children}</ThemeProvider>
    </QueryClientProvider>
  );
}
```

- [ ] **Step 7: Create sidebar component**

Create `src/components/sidebar.tsx`:

```tsx
import { NavLink } from "react-router-dom";
import {
  Cloud,
  FolderOpen,
  ArrowLeftRight,
  HardDrive,
  Activity,
  Settings,
  PanelLeftClose,
  PanelLeft,
} from "lucide-react";
import { useAppStore } from "../stores/app-store";
import { cn } from "../lib/utils";

const navItems = [
  { to: "/", icon: Cloud, label: "Remotes" },
  { to: "/browser", icon: FolderOpen, label: "Browser" },
  { to: "/copy-sync", icon: ArrowLeftRight, label: "Copy / Sync" },
  { to: "/transfers", icon: Activity, label: "Transfers" },
  { to: "/mounts", icon: HardDrive, label: "Mounts" },
  { to: "/settings", icon: Settings, label: "Settings" },
];

export function Sidebar() {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);
  const toggle = useAppStore((s) => s.toggleSidebar);

  return (
    <aside
      className={cn(
        "flex flex-col border-r border-border bg-sidebar-background h-full transition-all duration-200",
        collapsed ? "w-14" : "w-52"
      )}
    >
      <div className="flex items-center justify-between p-3 border-b border-sidebar-border">
        {!collapsed && (
          <span className="text-sm font-semibold text-sidebar-foreground truncate">
            StreamCloned
          </span>
        )}
        <button
          onClick={toggle}
          className="p-1 rounded hover:bg-sidebar-accent text-sidebar-foreground"
        >
          {collapsed ? <PanelLeft size={18} /> : <PanelLeftClose size={18} />}
        </button>
      </div>
      <nav className="flex-1 py-2">
        {navItems.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 px-3 py-2 mx-1 rounded-md text-sm transition-colors",
                isActive
                  ? "bg-sidebar-accent text-sidebar-accent-foreground font-medium"
                  : "text-sidebar-foreground hover:bg-sidebar-accent/50"
              )
            }
          >
            <Icon size={18} className="shrink-0" />
            {!collapsed && <span className="truncate">{label}</span>}
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
```

- [ ] **Step 8: Create page header component**

Create `src/components/page-header.tsx`:

```tsx
interface PageHeaderProps {
  title: string;
  description?: string;
  actions?: React.ReactNode;
}

export function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <div className="flex items-center justify-between pb-4 border-b border-border">
      <div>
        <h1 className="text-xl font-semibold">{title}</h1>
        {description && (
          <p className="text-sm text-muted-foreground mt-1">{description}</p>
        )}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
```

- [ ] **Step 9: Create stub pages for all features**

Create each stub page with the same pattern. Example for `src/features/remotes/pages/remotes-page.tsx`:

```tsx
import { PageHeader } from "../../../components/page-header";

export function RemotesPage() {
  return (
    <div className="p-6">
      <PageHeader
        title="Remotes"
        description="Manage your cloud storage connections"
      />
    </div>
  );
}
```

Create the same pattern for:
- `src/features/browser/pages/browser-page.tsx` — title: "Browser"
- `src/features/copy-sync/pages/copy-sync-page.tsx` — title: "Copy / Sync"
- `src/features/transfers/pages/transfers-page.tsx` — title: "Transfers"
- `src/features/mount/pages/mount-page.tsx` — title: "Mounts"
- `src/features/settings/pages/settings-page.tsx` — title: "Settings"
- `src/features/onboarding/pages/onboarding-page.tsx` — title: "Welcome to StreamCloned"

- [ ] **Step 10: Create router**

Create `src/app/router.tsx`:

```tsx
import { createBrowserRouter } from "react-router-dom";
import App from "./App";
import { RemotesPage } from "../features/remotes/pages/remotes-page";
import { BrowserPage } from "../features/browser/pages/browser-page";
import { CopySyncPage } from "../features/copy-sync/pages/copy-sync-page";
import { TransfersPage } from "../features/transfers/pages/transfers-page";
import { MountPage } from "../features/mount/pages/mount-page";
import { SettingsPage } from "../features/settings/pages/settings-page";

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
```

- [ ] **Step 11: Create App shell**

Create `src/app/App.tsx`:

```tsx
import { Outlet } from "react-router-dom";
import { Providers } from "./providers";
import { Sidebar } from "../components/sidebar";
import { Toaster } from "../components/ui/toaster";

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
```

**Note:** `Providers` wraps the content inside `App.tsx` (inside the router tree), NOT around `RouterProvider` in `main.tsx`. This ensures QueryClient and Theme are available to all routed components.

- [ ] **Step 12: Update main.tsx entry point**

Replace `src/main.tsx`:

```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import { RouterProvider } from "react-router-dom";
import { router } from "./app/router";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
```

**Important:** Providers must wrap `<Outlet />` inside `App.tsx`, not around `RouterProvider`. Components rendered by `createBrowserRouter` are NOT children of anything wrapping `RouterProvider` in the React tree.

- [ ] **Step 13: Create `src/lib/utils.ts`**

```ts
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

Install the deps if not already: `npm install clsx tailwind-merge`

- [ ] **Step 14: Verify the app renders with sidebar and routing**

```bash
npm run tauri dev
```

Expected: Window opens. Sidebar shows all nav items. Clicking them navigates to stub pages. Theme respects system preference.

- [ ] **Step 15: Commit**

```bash
git add -A
git commit -m "feat: app shell with sidebar navigation, routing, and theme

Sidebar with 6 nav items, light/dark/system theme, stub pages for
all features, app store with persisted preferences."
```

---

## Task 3: Rclone API Client & Types

**Goal:** Build the TypeScript HTTP client for the rclone RC API with typed request/response interfaces. This is the foundation every feature builds on.

**Files:**
- Create: `src/lib/rclone/client.ts`, `src/lib/rclone/types.ts`, `src/lib/rclone/remotes.ts`, `src/lib/rclone/operations.ts`, `src/lib/rclone/sync.ts`, `src/lib/rclone/jobs.ts`, `src/lib/rclone/mount.ts`, `src/lib/rclone/stats.ts`
- Test: `src/__tests__/lib/rclone/client.test.ts`

- [ ] **Step 1: Write rclone client test**

Create `src/__tests__/lib/rclone/client.test.ts`:

```ts
import { describe, it, expect, beforeEach, vi } from "vitest";
import { RcloneClient } from "../../../lib/rclone/client";

// Mock fetch globally
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("RcloneClient", () => {
  let client: RcloneClient;

  beforeEach(() => {
    client = new RcloneClient("http://localhost:5572");
    mockFetch.mockReset();
  });

  it("sends POST request with JSON body", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ remotes: ["gdrive:"] }),
    });

    const result = await client.call("config/listremotes", {});
    expect(mockFetch).toHaveBeenCalledWith("http://localhost:5572/config/listremotes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    expect(result).toEqual({ remotes: ["gdrive:"] });
  });

  it("throws RcloneError on non-ok response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: () => Promise.resolve({ error: "something broke", input: {}, path: "", status: 500 }),
    });

    await expect(client.call("rc/noop", {})).rejects.toThrow("something broke");
  });

  it("throws on network failure", async () => {
    mockFetch.mockRejectedValueOnce(new TypeError("Failed to fetch"));

    await expect(client.call("rc/noop", {})).rejects.toThrow("Failed to fetch");
  });

  it("health check calls rc/noop", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({}),
    });

    const alive = await client.healthCheck();
    expect(alive).toBe(true);
  });

  it("health check returns false on error", async () => {
    mockFetch.mockRejectedValueOnce(new Error("conn refused"));

    const alive = await client.healthCheck();
    expect(alive).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/__tests__/lib/rclone/client.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Create rclone types**

Create `src/lib/rclone/types.ts`:

```ts
// --- Error ---
export interface RcloneErrorResponse {
  error: string;
  input: Record<string, unknown>;
  path: string;
  status: number;
}

export class RcloneError extends Error {
  status: number;
  path: string;

  constructor(response: RcloneErrorResponse) {
    super(response.error);
    this.name = "RcloneError";
    this.status = response.status;
    this.path = response.path;
  }
}

// --- Remotes ---
export interface RcloneRemote {
  name: string;
  type: string;
  [key: string]: unknown;
}

export interface ListRemotesResponse {
  remotes: string[];
}

export interface ConfigDumpResponse {
  [remoteName: string]: Record<string, string>;
}

export interface ProviderOption {
  Name: string;
  Help: string;
  Default: unknown;
  Value: unknown;
  Type: string;
  Required: boolean;
  IsPassword: boolean;
  Advanced: boolean;
  Examples?: { Value: string; Help: string }[];
}

export interface Provider {
  Name: string;
  Description: string;
  Prefix: string;
  Options: ProviderOption[];
}

export interface ProvidersResponse {
  providers: Provider[];
}

// --- File Operations ---
export interface FileItem {
  Path: string;
  Name: string;
  Size: number;
  MimeType: string;
  ModTime: string;
  IsDir: boolean;
  ID?: string;
}

export interface ListResponse {
  list: FileItem[];
}

export interface StatResponse {
  item: FileItem;
}

export interface AboutResponse {
  total?: number;
  used?: number;
  trashed?: number;
  free?: number;
}

// --- Jobs ---
export interface Job {
  id: number;
  group: string;
  startTime: string;
  endTime: string;
  error: string;
  finished: boolean;
  success: boolean;
  duration: number;
  output: Record<string, unknown>;
}

export interface JobListResponse {
  jobids: number[];
}

export interface JobStatusResponse extends Job {}

// --- Stats ---
export interface TransferringFile {
  name: string;
  size: number;
  bytes: number;
  percentage: number;
  speed: number;
  speedAvg: number;
  eta: number;
  group: string;
}

export interface StatsResponse {
  speed: number;
  bytes: number;
  errors: number;
  fatalError: boolean;
  retryError: boolean;
  checks: number;
  transfers: number;
  deletes: number;
  renames: number;
  transferTime: number;
  elapsedTime: number;
  lastError: string;
  transferring?: TransferringFile[];
  checking?: string[];
  totalBytes: number;
  totalChecks: number;
  totalTransfers: number;
}

export interface BwLimitResponse {
  bytesPerSecond: number;
  bytesPerSecondTx: number;
  bytesPerSecondRx: number;
  rate: string;
}

// --- Mounts ---
export interface MountInfo {
  Fs: string;
  MountPoint: string;
  MountedOn: string;
}

export interface ListMountsResponse {
  mountPoints: MountInfo[];
}

// --- Async ---
export interface AsyncJobResponse {
  jobid: number;
}
```

- [ ] **Step 4: Implement rclone client**

Create `src/lib/rclone/client.ts`:

```ts
import { RcloneError, type RcloneErrorResponse } from "./types";

export class RcloneClient {
  constructor(private baseUrl: string) {}

  async call<T>(endpoint: string, params: Record<string, unknown>): Promise<T> {
    const response = await fetch(`${this.baseUrl}/${endpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });

    if (!response.ok) {
      const errorBody = (await response.json()) as RcloneErrorResponse;
      throw new RcloneError(errorBody);
    }

    return response.json() as Promise<T>;
  }

  async healthCheck(): Promise<boolean> {
    try {
      await this.call("rc/noop", {});
      return true;
    } catch {
      return false;
    }
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }
}

// Singleton instance — port updated at runtime after daemon starts
export const rclone = new RcloneClient("http://localhost:5572");
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npm test -- src/__tests__/lib/rclone/client.test.ts`
Expected: PASS

- [ ] **Step 6: Create rclone API modules**

Create `src/lib/rclone/remotes.ts`:

```ts
import { rclone } from "./client";
import type {
  ListRemotesResponse,
  ConfigDumpResponse,
  ProvidersResponse,
} from "./types";

export async function listRemotes(): Promise<string[]> {
  const res = await rclone.call<ListRemotesResponse>("config/listremotes", {});
  return res.remotes ?? [];
}

export async function configDump(): Promise<ConfigDumpResponse> {
  return rclone.call<ConfigDumpResponse>("config/dump", {});
}

export async function getProviders(): Promise<ProvidersResponse> {
  return rclone.call<ProvidersResponse>("config/providers", {});
}

export async function createRemote(
  name: string,
  type: string,
  parameters: Record<string, string>
): Promise<void> {
  await rclone.call("config/create", { name, type, parameters });
}

export async function updateRemote(
  name: string,
  parameters: Record<string, string>
): Promise<void> {
  await rclone.call("config/update", { name, parameters });
}

export async function deleteRemote(name: string): Promise<void> {
  await rclone.call("config/delete", { name });
}
```

Create `src/lib/rclone/operations.ts`:

```ts
import { rclone } from "./client";
import type {
  ListResponse,
  StatResponse,
  AboutResponse,
  FileItem,
} from "./types";

export async function listFiles(
  fs: string,
  remote: string
): Promise<FileItem[]> {
  const res = await rclone.call<ListResponse>("operations/list", {
    fs,
    remote,
  });
  return res.list ?? [];
}

export async function stat(fs: string, remote: string): Promise<FileItem> {
  const res = await rclone.call<StatResponse>("operations/stat", {
    fs,
    remote,
  });
  return res.item;
}

export async function mkdir(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/mkdir", { fs, remote });
}

export async function deleteFile(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/deletefile", { fs, remote });
}

export async function purge(fs: string, remote: string): Promise<void> {
  await rclone.call("operations/purge", { fs, remote });
}

export async function moveFile(
  srcFs: string,
  srcRemote: string,
  dstFs: string,
  dstRemote: string
): Promise<void> {
  await rclone.call("operations/movefile", {
    srcFs,
    srcRemote,
    dstFs,
    dstRemote,
  });
}

export async function copyFile(
  srcFs: string,
  srcRemote: string,
  dstFs: string,
  dstRemote: string
): Promise<void> {
  await rclone.call("operations/copyfile", {
    srcFs,
    srcRemote,
    dstFs,
    dstRemote,
  });
}

export async function about(fs: string): Promise<AboutResponse> {
  return rclone.call<AboutResponse>("operations/about", { fs });
}
```

Create `src/lib/rclone/sync.ts`:

```ts
import { rclone } from "./client";
import type { AsyncJobResponse } from "./types";

interface SyncOptions {
  srcFs: string;
  dstFs: string;
  _async?: boolean;
  _filter?: Record<string, unknown>;
  [key: string]: unknown;
}

export async function copy(opts: SyncOptions): Promise<AsyncJobResponse> {
  return rclone.call<AsyncJobResponse>("sync/copy", {
    ...opts,
    _async: opts._async ?? true,
  });
}

export async function sync(opts: SyncOptions): Promise<AsyncJobResponse> {
  return rclone.call<AsyncJobResponse>("sync/sync", {
    ...opts,
    _async: opts._async ?? true,
  });
}
```

Create `src/lib/rclone/jobs.ts`:

```ts
import { rclone } from "./client";
import type { JobListResponse, JobStatusResponse } from "./types";

export async function listJobs(): Promise<number[]> {
  const res = await rclone.call<JobListResponse>("job/list", {});
  return res.jobids ?? [];
}

export async function jobStatus(jobid: number): Promise<JobStatusResponse> {
  return rclone.call<JobStatusResponse>("job/status", { jobid });
}

export async function stopJob(jobid: number): Promise<void> {
  await rclone.call("job/stop", { jobid });
}
```

Create `src/lib/rclone/mount.ts`:

```ts
import { rclone } from "./client";
import type { ListMountsResponse, MountInfo } from "./types";

export async function mountRemote(
  fs: string,
  mountPoint: string,
  mountOpt?: Record<string, unknown>,
  vfsOpt?: Record<string, unknown>
): Promise<void> {
  await rclone.call("mount/mount", {
    fs,
    mountPoint,
    mountOpt: mountOpt ?? {},
    vfsOpt: vfsOpt ?? {},
  });
}

export async function unmountRemote(mountPoint: string): Promise<void> {
  await rclone.call("mount/unmount", { mountPoint });
}

export async function listMounts(): Promise<MountInfo[]> {
  const res = await rclone.call<ListMountsResponse>("mount/listmounts", {});
  return res.mountPoints ?? [];
}
```

Create `src/lib/rclone/stats.ts`:

```ts
import { rclone } from "./client";
import type { StatsResponse, BwLimitResponse } from "./types";

export async function getStats(group?: string): Promise<StatsResponse> {
  return rclone.call<StatsResponse>("core/stats", group ? { group } : {});
}

export async function setBandwidthLimit(
  rate: string
): Promise<BwLimitResponse> {
  return rclone.call<BwLimitResponse>("core/bwlimit", { rate });
}

export async function getBandwidthLimit(): Promise<BwLimitResponse> {
  return rclone.call<BwLimitResponse>("core/bwlimit", {});
}
```

- [ ] **Step 7: Create barrel export**

Create `src/lib/rclone/index.ts`:

```ts
export { rclone, RcloneClient } from "./client";
export * from "./types";
export * as remotes from "./remotes";
export * as operations from "./operations";
export * as sync from "./sync";
export * as jobs from "./jobs";
export * as mount from "./mount";
export * as stats from "./stats";
```

- [ ] **Step 8: Run all tests**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: rclone RC API client with typed interfaces

HTTP client, TypeScript types for all rclone responses, and API
modules for remotes, operations, sync, jobs, mount, and stats."
```

---

## Task 4: Rust Backend — Rclone Daemon Management

**Goal:** Implement the Rust commands to spawn, monitor, and stop the rclone daemon process. The frontend will invoke these via Tauri IPC.

**Files:**
- Create: `src-tauri/src/commands/mod.rs`, `src-tauri/src/commands/rclone.rs`
- Modify: `src-tauri/src/lib.rs`
- Create: `src/lib/tauri/rclone.ts`, `src/lib/tauri/events.ts`

- [ ] **Step 1: Create rclone commands module**

Create `src-tauri/src/commands/mod.rs`:

```rust
pub mod rclone;
```

- [ ] **Step 2: Implement rclone daemon commands**

Create `src-tauri/src/commands/rclone.rs`:

```rust
use std::net::TcpListener;
use std::sync::Mutex;
use tauri::State;
use tauri_plugin_shell::ShellExt;

pub struct RcloneState {
    pub port: Mutex<u16>,
    pub running: Mutex<bool>,
    pub child: Mutex<Option<tauri_plugin_shell::process::CommandChild>>,
}

impl Default for RcloneState {
    fn default() -> Self {
        Self {
            port: Mutex::new(5572),
            running: Mutex::new(false),
            child: Mutex::new(None),
        }
    }
}

fn find_available_port(start: u16) -> Option<u16> {
    for port in start..=start + 8 {
        if TcpListener::bind(("127.0.0.1", port)).is_ok() {
            return Some(port);
        }
    }
    None
}

#[tauri::command]
pub async fn start_rclone(
    app: tauri::AppHandle,
    state: State<'_, RcloneState>,
) -> Result<u16, String> {
    let port = find_available_port(5572).ok_or("No available port in range 5572-5580")?;

    let shell = app.shell();
    let (_, child) = shell
        .command("rclone")
        .args([
            "rcd",
            "--rc-no-auth",
            "--rc-addr",
            &format!("127.0.0.1:{}", port),
        ])
        .spawn()
        .map_err(|e| format!("Failed to start rclone: {}", e))?;

    *state.port.lock().unwrap() = port;
    *state.running.lock().unwrap() = true;
    *state.child.lock().unwrap() = Some(child);

    Ok(port)
}

#[tauri::command]
pub fn stop_rclone(state: State<'_, RcloneState>) -> Result<(), String> {
    if let Some(child) = state.child.lock().unwrap().take() {
        let _ = child.kill();
    }
    *state.running.lock().unwrap() = false;
    Ok(())
}

#[tauri::command]
pub fn get_rclone_port(state: State<'_, RcloneState>) -> u16 {
    *state.port.lock().unwrap()
}

#[tauri::command]
pub fn is_rclone_running(state: State<'_, RcloneState>) -> bool {
    *state.running.lock().unwrap()
}
```

- [ ] **Step 3: Register commands in lib.rs**

Update `src-tauri/src/lib.rs`:

```rust
mod commands;

use commands::rclone::RcloneState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(RcloneState::default())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            commands::rclone::start_rclone,
            commands::rclone::stop_rclone,
            commands::rclone::get_rclone_port,
            commands::rclone::is_rclone_running,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                let state = window.state::<RcloneState>();
                if let Some(child) = state.child.lock().unwrap().take() {
                    let _ = child.kill();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 4: Create TypeScript IPC wrappers**

Create `src/lib/tauri/rclone.ts`:

```ts
import { invoke } from "@tauri-apps/api/core";

export async function startRclone(): Promise<number> {
  return invoke<number>("start_rclone");
}

export async function getRclonePort(): Promise<number> {
  return invoke<number>("get_rclone_port");
}

export async function isRcloneRunning(): Promise<boolean> {
  return invoke<boolean>("is_rclone_running");
}
```

Create `src/lib/tauri/events.ts`:

```ts
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export function onDaemonStatusChange(
  callback: (running: boolean) => void
): Promise<UnlistenFn> {
  return listen<boolean>("daemon-status", (event) => {
    callback(event.payload);
  });
}
```

- [ ] **Step 5: Update shell permissions for rclone**

Update `src-tauri/capabilities/default.json` to allow executing the rclone binary. Add to the permissions array:

```json
"shell:allow-execute"
```

Also, add a scoped shell permission in `src-tauri/capabilities/default.json`. The shell plugin in Tauri v2 requires scoped commands. Add to `src-tauri/tauri.conf.json` under `plugins`:

```json
"plugins": {
  "shell": {
    "scope": [
      {
        "name": "rclone",
        "cmd": "rclone",
        "args": true
      }
    ]
  }
}
```

Note: The exact Tauri v2 shell scoping config may differ — check `https://v2.tauri.app/plugin/shell/` during implementation. The key requirement is that the `rclone` binary must be allowed to execute with any arguments.

- [ ] **Step 6: Verify Rust compiles**

```bash
cd src-tauri && cargo build && cd ..
```

Expected: Compiles without errors.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: Rust backend for rclone daemon management

Commands: start_rclone (with port detection), get_rclone_port,
is_rclone_running. TypeScript IPC wrappers for frontend."
```

---

## Task 5: Connection Banner & Daemon Startup Hook

**Goal:** When the app launches, automatically start the rclone daemon and show a connection status banner while connecting. This wires together the Rust backend and the rclone client.

**Files:**
- Create: `src/components/connection-banner.tsx`
- Create: `src/hooks/use-daemon.ts`
- Modify: `src/app/App.tsx`

- [ ] **Step 1: Create daemon hook**

Create `src/hooks/use-daemon.ts`:

```ts
import { useEffect, useState } from "react";
import { startRclone } from "../lib/tauri/rclone";
import { rclone } from "../lib/rclone/client";
import { useAppStore } from "../stores/app-store";

type DaemonStatus = "connecting" | "connected" | "error";

export function useDaemon() {
  const [status, setStatus] = useState<DaemonStatus>("connecting");
  const [error, setError] = useState<string | null>(null);
  const setRclonePort = useAppStore((s) => s.setRclonePort);

  useEffect(() => {
    let cancelled = false;

    async function connect() {
      setStatus("connecting");
      setError(null);

      try {
        const port = await startRclone();
        if (cancelled) return;
        setRclonePort(port);
        rclone.setBaseUrl(`http://localhost:${port}`);

        // Poll until daemon responds
        let attempts = 0;
        while (attempts < 30) {
          if (cancelled) return;
          const alive = await rclone.healthCheck();
          if (alive) {
            setStatus("connected");
            return;
          }
          attempts++;
          await new Promise((r) => setTimeout(r, 500));
        }

        throw new Error("Rclone daemon did not respond after 15 seconds");
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Unknown error");
        setStatus("error");
      }
    }

    connect();
    return () => { cancelled = true; };
  }, [setRclonePort]);

  const retry = () => {
    setStatus("connecting");
    setError(null);
    // Re-trigger by re-mounting — caller should key this component
  };

  return { status, error, retry };
}
```

- [ ] **Step 2: Create connection banner**

Create `src/components/connection-banner.tsx`:

```tsx
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
          <span>{error ?? "Failed to connect to rclone"}</span>
          <button
            onClick={onRetry}
            className="ml-auto flex items-center gap-1 hover:underline"
          >
            <RefreshCw size={12} />
            Retry
          </button>
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Wire into App shell**

Update `src/app/App.tsx`:

```tsx
import { Outlet } from "react-router-dom";
import { Sidebar } from "../components/sidebar";
import { ConnectionBanner } from "../components/connection-banner";
import { Toaster } from "../components/ui/toaster";
import { useDaemon } from "../hooks/use-daemon";

export default function App() {
  const { status, error, retry } = useDaemon();

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <ConnectionBanner status={status} error={error} onRetry={retry} />
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
      <Toaster />
    </div>
  );
}
```

- [ ] **Step 4: Verify in dev mode**

```bash
npm run tauri dev
```

Expected: App opens, shows "Connecting to rclone daemon..." banner. If rclone is installed on your system, it should eventually show "connected" (banner disappears). If rclone is not installed, it shows the error state with a retry button.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: auto-start rclone daemon on app launch

Connection banner shows connecting/error state. Daemon hook polls
until healthy. Port is dynamically detected and stored."
```

---

## Task 6: Remote Management — Home Screen

**Goal:** Build the home screen showing a grid of configured remotes with add/delete functionality.

**Files:**
- Create: All files in `src/features/remotes/`
- Create: `src/components/remote-icon.tsx`, `src/components/empty-state.tsx`

- [ ] **Step 1: Create TanStack Query hooks for remotes**

Create `src/features/remotes/hooks/use-remotes.ts`:

```ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import * as remotesApi from "../../../lib/rclone/remotes";

export function useRemotes() {
  return useQuery({
    queryKey: ["remotes"],
    queryFn: async () => {
      const names = await remotesApi.listRemotes();
      const config = await remotesApi.configDump();
      return names.map((name) => {
        const cleanName = name.replace(/:$/, "");
        return {
          name: cleanName,
          type: config[cleanName]?.type ?? "unknown",
          config: config[cleanName] ?? {},
        };
      });
    },
  });
}

export function useDeleteRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => remotesApi.deleteRemote(name),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["remotes"] });
    },
  });
}
```

Create `src/features/remotes/hooks/use-providers.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import * as remotesApi from "../../../lib/rclone/remotes";

export function useProviders() {
  return useQuery({
    queryKey: ["providers"],
    queryFn: () => remotesApi.getProviders(),
    staleTime: Infinity, // Provider list never changes during a session
  });
}
```

- [ ] **Step 2: Create remote icon component**

Create `src/components/remote-icon.tsx`:

```tsx
import {
  Cloud,
  HardDrive,
  Database,
  Server,
  FolderOpen,
} from "lucide-react";

const iconMap: Record<string, React.ElementType> = {
  drive: Cloud,
  s3: Database,
  dropbox: Cloud,
  onedrive: Cloud,
  b2: Database,
  sftp: Server,
  ftp: Server,
  local: FolderOpen,
};

interface RemoteIconProps {
  type: string;
  size?: number;
  className?: string;
}

export function RemoteIcon({ type, size = 24, className }: RemoteIconProps) {
  const Icon = iconMap[type] ?? HardDrive;
  return <Icon size={size} className={className} />;
}
```

- [ ] **Step 3: Create empty state component**

Create `src/components/empty-state.tsx`:

```tsx
import type { LucideIcon } from "lucide-react";

interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: React.ReactNode;
}

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <Icon size={48} className="text-muted-foreground/50 mb-4" />
      <h3 className="text-lg font-medium mb-1">{title}</h3>
      <p className="text-sm text-muted-foreground mb-4 max-w-sm">
        {description}
      </p>
      {action}
    </div>
  );
}
```

- [ ] **Step 4: Create remote card component**

Create `src/features/remotes/components/remote-card.tsx`:

```tsx
import { useNavigate } from "react-router-dom";
import { FolderOpen, HardDrive, ArrowLeftRight, Trash2 } from "lucide-react";
import { RemoteIcon } from "../../../components/remote-icon";

interface RemoteCardProps {
  name: string;
  type: string;
  onDelete: (name: string) => void;
}

export function RemoteCard({ name, type, onDelete }: RemoteCardProps) {
  const navigate = useNavigate();

  return (
    <div className="border border-border rounded-lg p-4 hover:bg-accent/50 transition-colors group">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3">
          <RemoteIcon type={type} size={28} className="text-muted-foreground" />
          <div>
            <h3 className="font-medium text-sm">{name}</h3>
            <p className="text-xs text-muted-foreground">{type}</p>
          </div>
        </div>
        <button
          onClick={() => onDelete(name)}
          className="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-all"
        >
          <Trash2 size={14} />
        </button>
      </div>
      <div className="flex gap-1">
        <button
          onClick={() => navigate(`/browser/${name}`)}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-secondary hover:bg-secondary/80 transition-colors"
        >
          <FolderOpen size={12} /> Browse
        </button>
        <button
          onClick={() => navigate(`/mounts?remote=${name}`)}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-secondary hover:bg-secondary/80 transition-colors"
        >
          <HardDrive size={12} /> Mount
        </button>
        <button
          onClick={() => navigate(`/copy-sync?src=${name}:`)}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-secondary hover:bg-secondary/80 transition-colors"
        >
          <ArrowLeftRight size={12} /> Sync
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Create delete confirmation dialog**

Create `src/features/remotes/components/delete-remote-dialog.tsx`:

```tsx
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../../../components/ui/alert-dialog";

interface DeleteRemoteDialogProps {
  remoteName: string | null;
  onConfirm: () => void;
  onCancel: () => void;
}

export function DeleteRemoteDialog({
  remoteName,
  onConfirm,
  onCancel,
}: DeleteRemoteDialogProps) {
  return (
    <AlertDialog open={!!remoteName} onOpenChange={(open) => !open && onCancel()}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete "{remoteName}"?</AlertDialogTitle>
          <AlertDialogDescription>
            This will remove the remote configuration. Files on the remote
            storage will not be affected.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={onCancel}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={onConfirm}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            Delete
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

Note: You'll need to add the `alert-dialog` shadcn component: `npx shadcn@latest add alert-dialog`

- [ ] **Step 6: Build the remotes page**

Replace `src/features/remotes/pages/remotes-page.tsx`:

```tsx
import { useState } from "react";
import { Plus, Cloud } from "lucide-react";
import { PageHeader } from "../../../components/page-header";
import { EmptyState } from "../../../components/empty-state";
import { Button } from "../../../components/ui/button";
import { RemoteCard } from "../components/remote-card";
import { DeleteRemoteDialog } from "../components/delete-remote-dialog";
import { useRemotes, useDeleteRemote } from "../hooks/use-remotes";

export function RemotesPage() {
  const { data: remotes, isLoading } = useRemotes();
  const deleteRemote = useDeleteRemote();
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

  const handleDelete = () => {
    if (deleteTarget) {
      deleteRemote.mutate(deleteTarget);
      setDeleteTarget(null);
    }
  };

  return (
    <div className="p-6">
      <PageHeader
        title="Remotes"
        description="Manage your cloud storage connections"
        actions={
          <Button size="sm">
            <Plus size={16} className="mr-1" /> Add Remote
          </Button>
        }
      />

      {isLoading ? (
        <div className="flex items-center justify-center py-16 text-muted-foreground">
          Loading remotes...
        </div>
      ) : !remotes?.length ? (
        <EmptyState
          icon={Cloud}
          title="No remotes configured"
          description="Add a cloud storage remote to get started with browsing, copying, and syncing files."
          action={
            <Button size="sm">
              <Plus size={16} className="mr-1" /> Add Remote
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mt-6">
          {remotes.map((remote) => (
            <RemoteCard
              key={remote.name}
              name={remote.name}
              type={remote.type}
              onDelete={setDeleteTarget}
            />
          ))}
        </div>
      )}

      <DeleteRemoteDialog
        remoteName={deleteTarget}
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  );
}
```

- [ ] **Step 7: Verify the remotes page renders**

```bash
npm run tauri dev
```

Expected: Home screen shows "No remotes configured" empty state if rclone has no remotes. If rclone has configured remotes, they appear as cards in a grid.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: remote management home screen

Grid of remote cards with browse/mount/sync quick actions,
delete confirmation dialog, empty state, provider icons."
```

---

## Task 7: File Browser

**Goal:** Build the file browser with list/grid views, breadcrumb navigation, and basic file operations (create folder, delete, upload, download).

**Files:**
- Create: All files in `src/features/browser/`
- Create: `src/components/path-breadcrumb.tsx`

- [ ] **Step 1: Create file list query hook**

Create `src/features/browser/hooks/use-file-list.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import * as ops from "../../../lib/rclone/operations";

export function useFileList(remote: string, path: string) {
  return useQuery({
    queryKey: ["files", remote, path],
    queryFn: () => ops.listFiles(`${remote}:`, path),
    enabled: !!remote,
  });
}
```

- [ ] **Step 2: Create selection hook**

Create `src/features/browser/hooks/use-selection.ts`:

```ts
import { useState, useCallback } from "react";
import type { FileItem } from "../../../lib/rclone/types";

export function useSelection(items: FileItem[]) {
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const toggle = useCallback(
    (name: string, event?: React.MouseEvent) => {
      setSelected((prev) => {
        const next = new Set(prev);
        if (event?.metaKey || event?.ctrlKey) {
          if (next.has(name)) next.delete(name);
          else next.add(name);
        } else if (event?.shiftKey && prev.size > 0) {
          const lastSelected = [...prev].pop()!;
          const lastIdx = items.findIndex((i) => i.Name === lastSelected);
          const currIdx = items.findIndex((i) => i.Name === name);
          const [start, end] = [
            Math.min(lastIdx, currIdx),
            Math.max(lastIdx, currIdx),
          ];
          for (let i = start; i <= end; i++) {
            next.add(items[i].Name);
          }
        } else {
          next.clear();
          next.add(name);
        }
        return next;
      });
    },
    [items]
  );

  const clear = useCallback(() => setSelected(new Set()), []);
  const selectAll = useCallback(
    () => setSelected(new Set(items.map((i) => i.Name))),
    [items]
  );

  return { selected, toggle, clear, selectAll };
}
```

- [ ] **Step 3: Create file operation mutation hooks**

Create `src/features/browser/hooks/use-file-operations.ts`:

```ts
import { useMutation, useQueryClient } from "@tanstack/react-query";
import * as ops from "../../../lib/rclone/operations";

export function useCreateFolder(remote: string, currentPath: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => {
      const fullPath = currentPath ? `${currentPath}/${name}` : name;
      return ops.mkdir(`${remote}:`, fullPath);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, currentPath] });
    },
  });
}

export function useDeleteItems(remote: string, currentPath: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (items: { name: string; isDir: boolean }[]) => {
      await Promise.all(
        items.map((item) => {
          const fullPath = currentPath ? `${currentPath}/${item.name}` : item.name;
          return item.isDir
            ? ops.purge(`${remote}:`, fullPath)
            : ops.deleteFile(`${remote}:`, fullPath);
        })
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, currentPath] });
    },
  });
}

export function useUploadFile(remote: string, currentPath: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ localPath }: { localPath: string }) => {
      const fileName = localPath.split("/").pop() ?? localPath.split("\\").pop() ?? "file";
      const dstPath = currentPath ? `${currentPath}/${fileName}` : fileName;
      await ops.copyFile("/", localPath, `${remote}:`, dstPath);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["files", remote, currentPath] });
    },
  });
}

export function useDownloadFile(remote: string) {
  return useMutation({
    mutationFn: async ({
      remotePath,
      localPath,
    }: {
      remotePath: string;
      localPath: string;
    }) => {
      await ops.copyFile(`${remote}:`, remotePath, "/", localPath);
    },
  });
}
```

- [ ] **Step 4: Create breadcrumb component**

Create `src/components/path-breadcrumb.tsx`:

```tsx
import { ChevronRight, Home } from "lucide-react";

interface PathBreadcrumbProps {
  remote: string;
  path: string;
  onNavigate: (path: string) => void;
}

export function PathBreadcrumb({
  remote,
  path,
  onNavigate,
}: PathBreadcrumbProps) {
  const segments = path ? path.split("/").filter(Boolean) : [];

  return (
    <div className="flex items-center gap-1 text-sm overflow-x-auto">
      <button
        onClick={() => onNavigate("")}
        className="flex items-center gap-1 px-2 py-1 rounded hover:bg-accent text-muted-foreground hover:text-foreground shrink-0"
      >
        <Home size={14} />
        <span>{remote}</span>
      </button>
      {segments.map((segment, idx) => {
        const segmentPath = segments.slice(0, idx + 1).join("/");
        return (
          <div key={segmentPath} className="flex items-center gap-1 shrink-0">
            <ChevronRight size={14} className="text-muted-foreground" />
            <button
              onClick={() => onNavigate(segmentPath)}
              className="px-2 py-1 rounded hover:bg-accent text-muted-foreground hover:text-foreground"
            >
              {segment}
            </button>
          </div>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 5: Create browser toolbar**

Create `src/features/browser/components/browser-toolbar.tsx`:

```tsx
import { useState } from "react";
import {
  List,
  Grid3X3,
  FolderPlus,
  Upload,
  Search,
} from "lucide-react";
import { Input } from "../../../components/ui/input";
import { Button } from "../../../components/ui/button";
import { open } from "@tauri-apps/plugin-dialog";

interface BrowserToolbarProps {
  viewMode: "list" | "grid";
  onViewModeChange: (mode: "list" | "grid") => void;
  filter: string;
  onFilterChange: (filter: string) => void;
  onCreateFolder: () => void;
  onUpload: (path: string) => void;
}

export function BrowserToolbar({
  viewMode,
  onViewModeChange,
  filter,
  onFilterChange,
  onCreateFolder,
  onUpload,
}: BrowserToolbarProps) {
  const [showFilter, setShowFilter] = useState(false);

  const handleUpload = async () => {
    const result = await open({ multiple: false });
    if (result && typeof result === "string") {
      onUpload(result);
    }
  };

  return (
    <div className="flex items-center gap-2 py-2">
      <div className="flex border border-border rounded-md">
        <button
          onClick={() => onViewModeChange("list")}
          className={`p-1.5 ${viewMode === "list" ? "bg-accent" : ""}`}
        >
          <List size={16} />
        </button>
        <button
          onClick={() => onViewModeChange("grid")}
          className={`p-1.5 ${viewMode === "grid" ? "bg-accent" : ""}`}
        >
          <Grid3X3 size={16} />
        </button>
      </div>

      <Button variant="ghost" size="sm" onClick={onCreateFolder}>
        <FolderPlus size={16} className="mr-1" /> New Folder
      </Button>
      <Button variant="ghost" size="sm" onClick={handleUpload}>
        <Upload size={16} className="mr-1" /> Upload
      </Button>

      <div className="ml-auto flex items-center gap-2">
        {showFilter ? (
          <Input
            value={filter}
            onChange={(e) => onFilterChange(e.target.value)}
            placeholder="Filter this folder..."
            className="w-48 h-8 text-sm"
            autoFocus
            onBlur={() => !filter && setShowFilter(false)}
          />
        ) : (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowFilter(true)}
          >
            <Search size={16} />
          </Button>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 6: Create file list view component**

Create `src/features/browser/components/file-list.tsx`:

```tsx
import { Folder, File, ChevronDown, ChevronUp } from "lucide-react";
import type { FileItem } from "../../../lib/rclone/types";
import { cn } from "../../../lib/utils";

interface FileListProps {
  files: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
  sortBy: string;
  sortDir: "asc" | "desc";
  onSort: (column: string) => void;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0)} ${units[i]}`;
}

function formatDate(iso: string): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function SortIcon({ column, sortBy, sortDir }: { column: string; sortBy: string; sortDir: "asc" | "desc" }) {
  if (column !== sortBy) return null;
  return sortDir === "asc" ? <ChevronUp size={14} /> : <ChevronDown size={14} />;
}

export function FileList({
  files,
  selected,
  onSelect,
  onOpen,
  sortBy,
  sortDir,
  onSort,
}: FileListProps) {
  return (
    <div className="border border-border rounded-md overflow-hidden">
      <div className="grid grid-cols-[1fr_100px_180px] gap-2 px-3 py-2 bg-muted/50 text-xs text-muted-foreground font-medium border-b border-border">
        <button onClick={() => onSort("name")} className="flex items-center gap-1 text-left">
          Name <SortIcon column="name" sortBy={sortBy} sortDir={sortDir} />
        </button>
        <button onClick={() => onSort("size")} className="flex items-center gap-1 text-right">
          Size <SortIcon column="size" sortBy={sortBy} sortDir={sortDir} />
        </button>
        <button onClick={() => onSort("date")} className="flex items-center gap-1 text-right">
          Modified <SortIcon column="date" sortBy={sortBy} sortDir={sortDir} />
        </button>
      </div>
      {files.map((file) => (
        <div
          key={file.Name}
          onClick={(e) => onSelect(file.Name, e)}
          onDoubleClick={() => onOpen(file)}
          className={cn(
            "grid grid-cols-[1fr_100px_180px] gap-2 px-3 py-2 text-sm cursor-pointer border-b border-border last:border-0 hover:bg-accent/50 transition-colors",
            selected.has(file.Name) && "bg-accent"
          )}
        >
          <div className="flex items-center gap-2 min-w-0">
            {file.IsDir ? (
              <Folder size={16} className="text-blue-500 shrink-0" />
            ) : (
              <File size={16} className="text-muted-foreground shrink-0" />
            )}
            <span className="truncate">{file.Name}</span>
          </div>
          <span className="text-right text-muted-foreground font-mono text-xs">
            {file.IsDir ? "—" : formatSize(file.Size)}
          </span>
          <span className="text-right text-muted-foreground text-xs">
            {formatDate(file.ModTime)}
          </span>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 6b: Create file grid view component**

Create `src/features/browser/components/file-grid.tsx`:

```tsx
import { Folder, File } from "lucide-react";
import type { FileItem } from "../../../lib/rclone/types";
import { cn } from "../../../lib/utils";

interface FileGridProps {
  files: FileItem[];
  selected: Set<string>;
  onSelect: (name: string, event: React.MouseEvent) => void;
  onOpen: (item: FileItem) => void;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0)} ${units[i]}`;
}

export function FileGrid({ files, selected, onSelect, onOpen }: FileGridProps) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2">
      {files.map((file) => (
        <div
          key={file.Name}
          onClick={(e) => onSelect(file.Name, e)}
          onDoubleClick={() => onOpen(file)}
          className={cn(
            "flex flex-col items-center gap-2 p-3 rounded-lg cursor-pointer hover:bg-accent/50 transition-colors text-center",
            selected.has(file.Name) && "bg-accent"
          )}
        >
          {file.IsDir ? (
            <Folder size={36} className="text-blue-500" />
          ) : (
            <File size={36} className="text-muted-foreground" />
          )}
          <span className="text-xs truncate w-full">{file.Name}</span>
          {!file.IsDir && (
            <span className="text-xs text-muted-foreground font-mono">
              {formatSize(file.Size)}
            </span>
          )}
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 7: Build the browser page**

Replace `src/features/browser/pages/browser-page.tsx`:

```tsx
import { useState, useMemo } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { FolderOpen } from "lucide-react";
import { PageHeader } from "../../../components/page-header";
import { PathBreadcrumb } from "../../../components/path-breadcrumb";
import { EmptyState } from "../../../components/empty-state";
import { BrowserToolbar } from "../components/browser-toolbar";
import { FileList } from "../components/file-list";
import { FileGrid } from "../components/file-grid";
import { useFileList } from "../hooks/use-file-list";
import { useSelection } from "../hooks/use-selection";
import {
  useCreateFolder,
  useDeleteItems,
  useUploadFile,
} from "../hooks/use-file-operations";
import type { FileItem } from "../../../lib/rclone/types";

export function BrowserPage() {
  const { remote = "", "*": splat = "" } = useParams();
  const path = splat;
  const navigate = useNavigate();

  const { data: files = [], isLoading } = useFileList(remote, path);
  const { selected, toggle, clear } = useSelection(files);

  const [viewMode, setViewMode] = useState<"list" | "grid">("list");
  const [filter, setFilter] = useState("");
  const [sortBy, setSortBy] = useState("name");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");

  const createFolder = useCreateFolder(remote, path);
  const deleteItems = useDeleteItems(remote, path);
  const uploadFile = useUploadFile(remote, path);

  const sortedFiles = useMemo(() => {
    let filtered = files.filter((f) =>
      f.Name.toLowerCase().includes(filter.toLowerCase())
    );
    // Directories first, then sort
    filtered.sort((a, b) => {
      if (a.IsDir !== b.IsDir) return a.IsDir ? -1 : 1;
      if (sortBy === "name") {
        const cmp = a.Name.localeCompare(b.Name);
        return sortDir === "asc" ? cmp : -cmp;
      }
      if (sortBy === "size") {
        const cmp = a.Size - b.Size;
        return sortDir === "asc" ? cmp : -cmp;
      }
      if (sortBy === "date") {
        const cmp =
          new Date(a.ModTime).getTime() - new Date(b.ModTime).getTime();
        return sortDir === "asc" ? cmp : -cmp;
      }
      return 0;
    });
    return filtered;
  }, [files, filter, sortBy, sortDir]);

  const handleSort = (column: string) => {
    if (sortBy === column) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortBy(column);
      setSortDir("asc");
    }
  };

  const handleOpen = (item: FileItem) => {
    if (item.IsDir) {
      const newPath = path ? `${path}/${item.Name}` : item.Name;
      navigate(`/browser/${remote}/${newPath}`);
      clear();
    }
  };

  const handleNavigate = (newPath: string) => {
    navigate(`/browser/${remote}/${newPath}`);
    clear();
  };

  const [showCreateFolder, setShowCreateFolder] = useState(false);
  const [newFolderName, setNewFolderName] = useState("");

  const handleCreateFolder = () => {
    setNewFolderName("");
    setShowCreateFolder(true);
  };

  const confirmCreateFolder = () => {
    if (newFolderName.trim()) {
      createFolder.mutate(newFolderName.trim());
      setShowCreateFolder(false);
    }
  };

  const handleUpload = (localPath: string) => {
    uploadFile.mutate({ localPath });
  };

  if (!remote) {
    return (
      <div className="p-6">
        <PageHeader title="Browser" />
        <EmptyState
          icon={FolderOpen}
          title="No remote selected"
          description="Select a remote from the Remotes page to start browsing."
        />
      </div>
    );
  }

  return (
    <div className="p-6 flex flex-col gap-2">
      <PageHeader title="Browser" />
      <PathBreadcrumb
        remote={remote}
        path={path}
        onNavigate={handleNavigate}
      />
      <BrowserToolbar
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        filter={filter}
        onFilterChange={setFilter}
        onCreateFolder={handleCreateFolder}
        onUpload={handleUpload}
      />

      {isLoading ? (
        <div className="py-8 text-center text-muted-foreground">
          Loading...
        </div>
      ) : sortedFiles.length === 0 ? (
        <EmptyState
          icon={FolderOpen}
          title="Empty folder"
          description={
            filter ? "No files match your filter." : "This folder is empty."
          }
        />
      ) : viewMode === "list" ? (
        <FileList
          files={sortedFiles}
          selected={selected}
          onSelect={toggle}
          onOpen={handleOpen}
          sortBy={sortBy}
          sortDir={sortDir}
          onSort={handleSort}
        />
      ) : (
        <FileGrid
          files={sortedFiles}
          selected={selected}
          onSelect={toggle}
          onOpen={handleOpen}
        />
      )}

      {selected.size > 0 && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-2 bg-card border border-border rounded-lg shadow-lg px-4 py-2 text-sm">
          <span className="text-muted-foreground">
            {selected.size} selected
          </span>
          <button
            onClick={() => {
              if (confirm(`Delete ${selected.size} item(s)?`)) {
                const items = files
                  .filter((f) => selected.has(f.Name))
                  .map((f) => ({ name: f.Name, isDir: f.IsDir }));
                deleteItems.mutate(items);
                clear();
              }
            }}
            className="text-destructive hover:underline"
          >
            Delete
          </button>
          <button onClick={clear} className="text-muted-foreground hover:underline">
            Clear
          </button>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 8: Verify file browser works**

```bash
npm run tauri dev
```

Expected: Navigate to a remote via the "Browse" button on a remote card. File browser shows breadcrumbs, toolbar, and file listing. Clicking folders navigates into them. Filter input works.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: file browser with list view, breadcrumbs, and file operations

List view with sortable columns, breadcrumb navigation, create folder,
upload via Tauri dialog, delete selected items, client-side filter."
```

---

## Task 8: Copy & Sync Page

**Goal:** Build the copy/sync page with source/destination pickers and dry run support.

**Prerequisites:** This task requires the transfer store. Create `src/stores/transfer-store.ts` first (the full implementation is in Task 9, Steps 1-3). Complete those steps before proceeding here, or simply create the store file from Task 9's Step 3 code now.

**Files:**
- Create: All files in `src/features/copy-sync/`
- Create: `src/features/copy-sync/hooks/use-sync.ts`
- Create: `src/stores/transfer-store.ts` (if not already created)

- [ ] **Step 0: Create transfer store (prerequisite from Task 9)**

If `src/stores/transfer-store.ts` does not exist yet, create it now using the code from Task 9, Step 3. The `useStartSync` hook in this task imports `useTransferStore`.

- [ ] **Step 1: Create sync mutation hook**

Create `src/features/copy-sync/hooks/use-sync.ts`:

```ts
import { useMutation } from "@tanstack/react-query";
import * as syncApi from "../../../lib/rclone/sync";
import { useTransferStore } from "../../../stores/transfer-store";

interface SyncParams {
  srcFs: string;
  dstFs: string;
  operation: "copy" | "sync";
  dryRun?: boolean;
}

export function useStartSync() {
  const addTransfer = useTransferStore((s) => s.addTransfer);

  return useMutation({
    mutationFn: async ({ srcFs, dstFs, operation, dryRun }: SyncParams) => {
      const opts = {
        srcFs,
        dstFs,
        _async: true,
        ...(dryRun ? { dryRun: true } : {}),
      };
      const result =
        operation === "copy"
          ? await syncApi.copy(opts)
          : await syncApi.sync(opts);
      return result;
    },
    onSuccess: (result, variables) => {
      if (!variables.dryRun) {
        addTransfer({
          jobId: result.jobid,
          operation: variables.operation,
          srcFs: variables.srcFs,
          dstFs: variables.dstFs,
          startedAt: new Date().toISOString(),
        });
      }
    },
  });
}
```

- [ ] **Step 2: Create path picker component**

Create `src/features/copy-sync/components/path-picker.tsx`:

```tsx
import { useState } from "react";
import { FolderOpen } from "lucide-react";
import { Input } from "../../../components/ui/input";
import { Label } from "../../../components/ui/label";
import { Button } from "../../../components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../../../components/ui/select";
import { useRemotes } from "../../remotes/hooks/use-remotes";

interface PathPickerProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
}

export function PathPicker({ label, value, onChange }: PathPickerProps) {
  const { data: remotes = [] } = useRemotes();
  const [remote, setRemote] = useState("");
  const [path, setPath] = useState("");

  const handleRemoteChange = (r: string) => {
    setRemote(r);
    onChange(`${r}:${path}`);
  };

  const handlePathChange = (p: string) => {
    setPath(p);
    onChange(`${remote}:${p}`);
  };

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="flex gap-2">
        <Select value={remote} onValueChange={handleRemoteChange}>
          <SelectTrigger className="w-40">
            <SelectValue placeholder="Remote" />
          </SelectTrigger>
          <SelectContent>
            {remotes.map((r) => (
              <SelectItem key={r.name} value={r.name}>
                {r.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Input
          value={path}
          onChange={(e) => handlePathChange(e.target.value)}
          placeholder="path/to/folder"
          className="flex-1 font-mono text-sm"
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Build the copy/sync page**

Replace `src/features/copy-sync/pages/copy-sync-page.tsx`:

```tsx
import { useState } from "react";
import { useSearchParams, useNavigate } from "react-router-dom";
import { ArrowRight, Play } from "lucide-react";
import { PageHeader } from "../../../components/page-header";
import { Button } from "../../../components/ui/button";
import { Label } from "../../../components/ui/label";
import { PathPicker } from "../components/path-picker";
import { useStartSync } from "../hooks/use-sync";

export function CopySyncPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const [srcFs, setSrcFs] = useState(searchParams.get("src") ?? "");
  const [dstFs, setDstFs] = useState("");
  const [operation, setOperation] = useState<"copy" | "sync">("copy");
  const [dryRun, setDryRun] = useState(false);

  const startSync = useStartSync();

  const handleStart = () => {
    if (!srcFs || !dstFs) return;
    startSync.mutate(
      { srcFs, dstFs, operation, dryRun },
      {
        onSuccess: () => {
          if (!dryRun) navigate("/transfers");
        },
      }
    );
  };

  return (
    <div className="p-6 max-w-2xl">
      <PageHeader
        title="Copy / Sync"
        description="Transfer files between remotes"
      />

      <div className="mt-6 space-y-6">
        <PathPicker label="Source" value={srcFs} onChange={setSrcFs} />

        <div className="flex justify-center">
          <ArrowRight size={20} className="text-muted-foreground" />
        </div>

        <PathPicker label="Destination" value={dstFs} onChange={setDstFs} />

        <div className="space-y-3">
          <div className="flex gap-2">
            <button
              onClick={() => setOperation("copy")}
              className={`px-3 py-1.5 rounded text-sm border ${
                operation === "copy"
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border"
              }`}
            >
              Copy
            </button>
            <button
              onClick={() => setOperation("sync")}
              className={`px-3 py-1.5 rounded text-sm border ${
                operation === "sync"
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border"
              }`}
            >
              Sync
            </button>
          </div>

          {operation === "sync" && (
            <p className="text-xs text-yellow-600 dark:text-yellow-400">
              Sync will delete files in the destination that don't exist in the
              source.
            </p>
          )}

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={dryRun}
              onChange={(e) => setDryRun(e.target.checked)}
              className="rounded"
            />
            Dry run (preview changes without executing)
          </label>
        </div>

        <Button
          onClick={handleStart}
          disabled={!srcFs || !dstFs || startSync.isPending}
          className="w-full"
        >
          <Play size={16} className="mr-2" />
          {startSync.isPending
            ? "Starting..."
            : dryRun
              ? "Preview Changes"
              : `Start ${operation === "copy" ? "Copy" : "Sync"}`}
        </Button>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify copy/sync page renders**

```bash
npm run tauri dev
```

Expected: Navigate to Copy/Sync. Source and destination pickers show available remotes. Copy/Sync toggle works. Dry run checkbox toggles.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: copy & sync page with source/dest pickers and dry run

Path pickers with remote dropdown + path input, operation toggle,
dry run mode, auto-redirect to transfers on start."
```

---

## Task 9: Transfer Queue & Store

**Goal:** Build the transfer store and transfers page showing active/completed jobs with real-time progress polling.

**Files:**
- Create: `src/stores/transfer-store.ts`, `src/__tests__/stores/transfer-store.test.ts`
- Create: All files in `src/features/transfers/`

- [ ] **Step 1: Write transfer store test**

Create `src/__tests__/stores/transfer-store.test.ts`:

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { useTransferStore } from "../../stores/transfer-store";

describe("transferStore", () => {
  beforeEach(() => {
    useTransferStore.setState({ transfers: [] });
  });

  it("adds a transfer", () => {
    useTransferStore.getState().addTransfer({
      jobId: 1,
      operation: "copy",
      srcFs: "gdrive:photos",
      dstFs: "s3:backup",
      startedAt: "2026-03-23T00:00:00Z",
    });
    expect(useTransferStore.getState().transfers).toHaveLength(1);
    expect(useTransferStore.getState().transfers[0].status).toBe("active");
  });

  it("marks transfer as completed", () => {
    useTransferStore.getState().addTransfer({
      jobId: 1,
      operation: "copy",
      srcFs: "a:",
      dstFs: "b:",
      startedAt: "2026-03-23T00:00:00Z",
    });
    useTransferStore.getState().completeTransfer(1, true);
    expect(useTransferStore.getState().transfers[0].status).toBe("completed");
  });

  it("marks transfer as failed", () => {
    useTransferStore.getState().addTransfer({
      jobId: 1,
      operation: "sync",
      srcFs: "a:",
      dstFs: "b:",
      startedAt: "2026-03-23T00:00:00Z",
    });
    useTransferStore.getState().completeTransfer(1, false, "Network error");
    const t = useTransferStore.getState().transfers[0];
    expect(t.status).toBe("failed");
    expect(t.error).toBe("Network error");
  });

  it("removes transfer", () => {
    useTransferStore.getState().addTransfer({
      jobId: 1,
      operation: "copy",
      srcFs: "a:",
      dstFs: "b:",
      startedAt: "2026-03-23T00:00:00Z",
    });
    useTransferStore.getState().removeTransfer(1);
    expect(useTransferStore.getState().transfers).toHaveLength(0);
  });

  it("clears completed transfers", () => {
    const store = useTransferStore.getState();
    store.addTransfer({ jobId: 1, operation: "copy", srcFs: "a:", dstFs: "b:", startedAt: "" });
    store.addTransfer({ jobId: 2, operation: "copy", srcFs: "c:", dstFs: "d:", startedAt: "" });
    store.completeTransfer(1, true);
    store.clearCompleted();
    expect(useTransferStore.getState().transfers).toHaveLength(1);
    expect(useTransferStore.getState().transfers[0].jobId).toBe(2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/__tests__/stores/transfer-store.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement transfer store**

Create `src/stores/transfer-store.ts`:

```ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

export type TransferStatus = "active" | "completed" | "failed" | "cancelled";

export interface Transfer {
  jobId: number;
  operation: "copy" | "sync";
  srcFs: string;
  dstFs: string;
  startedAt: string;
  completedAt?: string;
  status: TransferStatus;
  error?: string;
}

interface TransferState {
  transfers: Transfer[];
  addTransfer: (t: Omit<Transfer, "status">) => void;
  completeTransfer: (jobId: number, success: boolean, error?: string) => void;
  cancelTransfer: (jobId: number) => void;
  removeTransfer: (jobId: number) => void;
  clearCompleted: () => void;
}

export const useTransferStore = create<TransferState>()(
  persist(
    (set) => ({
      transfers: [],
      addTransfer: (t) =>
        set((state) => ({
          transfers: [{ ...t, status: "active" as const }, ...state.transfers],
        })),
      completeTransfer: (jobId, success, error) =>
        set((state) => ({
          transfers: state.transfers.map((t) =>
            t.jobId === jobId
              ? {
                  ...t,
                  status: success ? ("completed" as const) : ("failed" as const),
                  completedAt: new Date().toISOString(),
                  error,
                }
              : t
          ),
        })),
      cancelTransfer: (jobId) =>
        set((state) => ({
          transfers: state.transfers.map((t) =>
            t.jobId === jobId
              ? { ...t, status: "cancelled" as const, completedAt: new Date().toISOString() }
              : t
          ),
        })),
      removeTransfer: (jobId) =>
        set((state) => ({
          transfers: state.transfers.filter((t) => t.jobId !== jobId),
        })),
      clearCompleted: () =>
        set((state) => ({
          transfers: state.transfers.filter((t) => t.status === "active"),
        })),
    }),
    { name: "streamcloned-transfers" }
  )
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/__tests__/stores/transfer-store.test.ts`
Expected: PASS

- [ ] **Step 5: Create transfer polling hook**

Create `src/features/transfers/hooks/use-transfers.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import * as jobs from "../../../lib/rclone/jobs";
import * as statsApi from "../../../lib/rclone/stats";
import { useTransferStore } from "../../../stores/transfer-store";

export function useActiveTransfers() {
  const transfers = useTransferStore((s) => s.transfers);
  const activeTransfers = transfers.filter((t) => t.status === "active");
  const completeTransfer = useTransferStore((s) => s.completeTransfer);

  // Poll job status for active transfers
  useQuery({
    queryKey: ["job-status", activeTransfers.map((t) => t.jobId)],
    queryFn: async () => {
      const results = await Promise.all(
        activeTransfers.map(async (t) => {
          try {
            const status = await jobs.jobStatus(t.jobId);
            if (status.finished) {
              completeTransfer(
                t.jobId,
                status.success,
                status.error || undefined
              );
            }
            return status;
          } catch {
            return null;
          }
        })
      );
      return results;
    },
    enabled: activeTransfers.length > 0,
    refetchInterval: activeTransfers.length > 0 ? 2000 : false,
  });

  return transfers;
}

export function useTransferStats() {
  const transfers = useTransferStore((s) => s.transfers);
  const hasActive = transfers.some((t) => t.status === "active");

  return useQuery({
    queryKey: ["transfer-stats"],
    queryFn: () => statsApi.getStats(),
    enabled: hasActive,
    refetchInterval: hasActive ? 2000 : false,
  });
}
```

- [ ] **Step 6: Create transfer item component**

Create `src/features/transfers/components/transfer-item.tsx`:

```tsx
import {
  Copy,
  RefreshCw,
  X,
  CheckCircle2,
  XCircle,
  Loader2,
  Ban,
} from "lucide-react";
import type { Transfer } from "../../../stores/transfer-store";
import * as jobsApi from "../../../lib/rclone/jobs";
import { useTransferStore } from "../../../stores/transfer-store";

interface TransferItemProps {
  transfer: Transfer;
}

const statusIcons = {
  active: <Loader2 size={16} className="animate-spin text-blue-500" />,
  completed: <CheckCircle2 size={16} className="text-green-500" />,
  failed: <XCircle size={16} className="text-destructive" />,
  cancelled: <Ban size={16} className="text-muted-foreground" />,
};

export function TransferItem({ transfer }: TransferItemProps) {
  const cancelTransfer = useTransferStore((s) => s.cancelTransfer);

  const handleCancel = async () => {
    try {
      await jobsApi.stopJob(transfer.jobId);
      cancelTransfer(transfer.jobId);
    } catch {
      // Job may have already finished
    }
  };

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-b border-border last:border-0">
      {statusIcons[transfer.status]}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 text-sm">
          {transfer.operation === "copy" ? (
            <Copy size={14} className="shrink-0" />
          ) : (
            <RefreshCw size={14} className="shrink-0" />
          )}
          <span className="font-mono text-xs truncate">{transfer.srcFs}</span>
          <span className="text-muted-foreground">→</span>
          <span className="font-mono text-xs truncate">{transfer.dstFs}</span>
        </div>
        {transfer.error && (
          <p className="text-xs text-destructive mt-1">{transfer.error}</p>
        )}
      </div>
      {transfer.status === "active" && (
        <button
          onClick={handleCancel}
          className="p-1 hover:bg-destructive/10 rounded text-muted-foreground hover:text-destructive"
        >
          <X size={14} />
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 7: Build the transfers page**

Replace `src/features/transfers/pages/transfers-page.tsx`:

```tsx
import { Activity } from "lucide-react";
import { PageHeader } from "../../../components/page-header";
import { EmptyState } from "../../../components/empty-state";
import { Button } from "../../../components/ui/button";
import { TransferItem } from "../components/transfer-item";
import { useActiveTransfers, useTransferStats } from "../hooks/use-transfers";
import { useTransferStore } from "../../../stores/transfer-store";

export function TransfersPage() {
  const transfers = useActiveTransfers();
  const { data: stats } = useTransferStats();
  const clearCompleted = useTransferStore((s) => s.clearCompleted);

  const active = transfers.filter((t) => t.status === "active");
  const completed = transfers.filter((t) => t.status !== "active");

  return (
    <div className="p-6">
      <PageHeader
        title="Transfers"
        description={
          stats && active.length > 0
            ? `${formatSpeed(stats.speed)} · ${stats.transfers} files transferred`
            : undefined
        }
        actions={
          completed.length > 0 ? (
            <Button variant="ghost" size="sm" onClick={clearCompleted}>
              Clear Completed
            </Button>
          ) : undefined
        }
      />

      {transfers.length === 0 ? (
        <EmptyState
          icon={Activity}
          title="No transfers"
          description="Start a copy or sync operation to see transfer progress here."
        />
      ) : (
        <div className="mt-4 border border-border rounded-md">
          {active.length > 0 && (
            <>
              <div className="px-4 py-2 text-xs font-medium text-muted-foreground bg-muted/50 border-b border-border">
                Active ({active.length})
              </div>
              {active.map((t) => (
                <TransferItem key={t.jobId} transfer={t} />
              ))}
            </>
          )}
          {completed.length > 0 && (
            <>
              <div className="px-4 py-2 text-xs font-medium text-muted-foreground bg-muted/50 border-b border-border">
                Completed ({completed.length})
              </div>
              {completed.map((t) => (
                <TransferItem key={t.jobId} transfer={t} />
              ))}
            </>
          )}
        </div>
      )}
    </div>
  );
}

function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec === 0) return "0 B/s";
  const units = ["B/s", "KB/s", "MB/s", "GB/s"];
  const i = Math.floor(Math.log(bytesPerSec) / Math.log(1024));
  return `${(bytesPerSec / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}
```

- [ ] **Step 8: Run all tests**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 9: Verify transfers page**

```bash
npm run tauri dev
```

Expected: Transfers page shows empty state. After starting a copy/sync, transfers appear with real-time status polling.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: transfer queue with real-time job status polling

Zustand store for transfer history, TanStack Query polling for
active job status, cancel support, clear completed, speed stats."
```

---

## Task 10: Mount Manager

**Goal:** Build the mount manager page with mount/unmount, auto-mount config, and the mount store.

**Files:**
- Create: `src/stores/mount-store.ts`, `src/__tests__/stores/mount-store.test.ts`
- Create: All files in `src/features/mount/`

- [ ] **Step 1: Write mount store test**

Create `src/__tests__/stores/mount-store.test.ts`:

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { useMountStore } from "../../stores/mount-store";

describe("mountStore", () => {
  beforeEach(() => {
    useMountStore.setState({ configs: [] });
  });

  it("adds a mount config", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/Volumes/gdrive",
      vfsMode: "read-write",
      autoMount: false,
    });
    expect(useMountStore.getState().configs).toHaveLength(1);
  });

  it("removes a mount config", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/Volumes/gdrive",
      vfsMode: "read-write",
      autoMount: false,
    });
    useMountStore.getState().removeConfig("/Volumes/gdrive");
    expect(useMountStore.getState().configs).toHaveLength(0);
  });

  it("toggles auto-mount", () => {
    useMountStore.getState().addConfig({
      remote: "gdrive:",
      mountPoint: "/Volumes/gdrive",
      vfsMode: "read-only",
      autoMount: false,
    });
    useMountStore.getState().toggleAutoMount("/Volumes/gdrive");
    expect(useMountStore.getState().configs[0].autoMount).toBe(true);
  });
});
```

- [ ] **Step 2: Run test — expect fail**

Run: `npm test -- src/__tests__/stores/mount-store.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement mount store**

Create `src/stores/mount-store.ts`:

```ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

export interface MountConfig {
  remote: string;
  mountPoint: string;
  vfsMode: "read-only" | "read-write";
  autoMount: boolean;
}

interface MountState {
  configs: MountConfig[];
  addConfig: (config: MountConfig) => void;
  removeConfig: (mountPoint: string) => void;
  toggleAutoMount: (mountPoint: string) => void;
}

export const useMountStore = create<MountState>()(
  persist(
    (set) => ({
      configs: [],
      addConfig: (config) =>
        set((state) => ({ configs: [...state.configs, config] })),
      removeConfig: (mountPoint) =>
        set((state) => ({
          configs: state.configs.filter((c) => c.mountPoint !== mountPoint),
        })),
      toggleAutoMount: (mountPoint) =>
        set((state) => ({
          configs: state.configs.map((c) =>
            c.mountPoint === mountPoint
              ? { ...c, autoMount: !c.autoMount }
              : c
          ),
        })),
    }),
    { name: "streamcloned-mounts" }
  )
);
```

- [ ] **Step 4: Run test — expect pass**

Run: `npm test -- src/__tests__/stores/mount-store.test.ts`
Expected: PASS

- [ ] **Step 5: Create mount hooks**

Create `src/features/mount/hooks/use-mounts.ts`:

```ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import * as mountApi from "../../../lib/rclone/mount";
import { useMountStore } from "../../../stores/mount-store";

export function useActiveMounts() {
  return useQuery({
    queryKey: ["mounts"],
    queryFn: () => mountApi.listMounts(),
    refetchInterval: 10_000,
  });
}

export function useMountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      fs,
      mountPoint,
      vfsMode,
    }: {
      fs: string;
      mountPoint: string;
      vfsMode: string;
    }) =>
      mountApi.mountRemote(fs, mountPoint, {}, { CacheMode: vfsMode === "read-write" ? "full" : "off" }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mounts"] });
    },
  });
}

export function useUnmountRemote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (mountPoint: string) => mountApi.unmountRemote(mountPoint),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mounts"] });
    },
  });
}
```

- [ ] **Step 6: Create mount item component**

Create `src/features/mount/components/mount-item.tsx`:

```tsx
import { HardDrive, Unplug } from "lucide-react";
import type { MountConfig } from "../../../stores/mount-store";
import { useMountStore } from "../../../stores/mount-store";
import { useUnmountRemote } from "../hooks/use-mounts";

interface MountItemProps {
  config: MountConfig;
  isActive: boolean;
  onMount: () => void;
}

export function MountItem({ config, isActive, onMount }: MountItemProps) {
  const toggleAutoMount = useMountStore((s) => s.toggleAutoMount);
  const removeConfig = useMountStore((s) => s.removeConfig);
  const unmount = useUnmountRemote();

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-b border-border last:border-0">
      <HardDrive
        size={18}
        className={isActive ? "text-green-500" : "text-muted-foreground"}
      />
      <div className="flex-1 min-w-0">
        <div className="text-sm font-medium">{config.remote}</div>
        <div className="text-xs text-muted-foreground font-mono">
          {config.mountPoint}
        </div>
      </div>
      <label className="flex items-center gap-1 text-xs text-muted-foreground">
        <input
          type="checkbox"
          checked={config.autoMount}
          onChange={() => toggleAutoMount(config.mountPoint)}
          className="rounded"
        />
        Auto
      </label>
      {isActive ? (
        <button
          onClick={() => unmount.mutate(config.mountPoint)}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-destructive/10 text-destructive hover:bg-destructive/20"
        >
          <Unplug size={12} /> Unmount
        </button>
      ) : (
        <button
          onClick={onMount}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-primary/10 text-primary hover:bg-primary/20"
        >
          <HardDrive size={12} /> Mount
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 7: Create add mount dialog**

Create `src/features/mount/components/add-mount-dialog.tsx`:

```tsx
import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "../../../components/ui/dialog";
import { Button } from "../../../components/ui/button";
import { Input } from "../../../components/ui/input";
import { Label } from "../../../components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../../../components/ui/select";
import { useRemotes } from "../../remotes/hooks/use-remotes";
import { open } from "@tauri-apps/plugin-dialog";

interface AddMountDialogProps {
  open: boolean;
  onClose: () => void;
  onAdd: (remote: string, mountPoint: string, vfsMode: "read-only" | "read-write") => void;
}

export function AddMountDialog({ open: isOpen, onClose, onAdd }: AddMountDialogProps) {
  const { data: remotes = [] } = useRemotes();
  const [remote, setRemote] = useState("");
  const [mountPoint, setMountPoint] = useState("");
  const [vfsMode, setVfsMode] = useState<"read-only" | "read-write">("read-write");

  const handleBrowse = async () => {
    const dir = await open({ directory: true });
    if (dir) setMountPoint(dir);
  };

  const handleAdd = () => {
    if (remote && mountPoint) {
      onAdd(`${remote}:`, mountPoint, vfsMode);
      setRemote("");
      setMountPoint("");
      onClose();
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Mount</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label>Remote</Label>
            <Select value={remote} onValueChange={setRemote}>
              <SelectTrigger>
                <SelectValue placeholder="Select remote" />
              </SelectTrigger>
              <SelectContent>
                {remotes.map((r) => (
                  <SelectItem key={r.name} value={r.name}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Mount Point</Label>
            <div className="flex gap-2">
              <Input
                value={mountPoint}
                onChange={(e) => setMountPoint(e.target.value)}
                placeholder="/Volumes/my-remote"
                className="font-mono text-sm"
              />
              <Button variant="outline" onClick={handleBrowse}>
                Browse
              </Button>
            </div>
          </div>
          <div className="space-y-2">
            <Label>Mode</Label>
            <Select value={vfsMode} onValueChange={(v) => setVfsMode(v as "read-only" | "read-write")}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="read-only">Read Only</SelectItem>
                <SelectItem value="read-write">Read / Write</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleAdd} disabled={!remote || !mountPoint}>
            Add Mount
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 8: Build the mount page**

Replace `src/features/mount/pages/mount-page.tsx`:

```tsx
import { useState } from "react";
import { Plus, HardDrive } from "lucide-react";
import { PageHeader } from "../../../components/page-header";
import { EmptyState } from "../../../components/empty-state";
import { Button } from "../../../components/ui/button";
import { MountItem } from "../components/mount-item";
import { AddMountDialog } from "../components/add-mount-dialog";
import { useMountStore } from "../../../stores/mount-store";
import { useActiveMounts, useMountRemote } from "../hooks/use-mounts";

export function MountPage() {
  const configs = useMountStore((s) => s.configs);
  const addConfig = useMountStore((s) => s.addConfig);
  const { data: activeMounts = [] } = useActiveMounts();
  const mountRemote = useMountRemote();
  const [showAdd, setShowAdd] = useState(false);

  const activeMountPoints = new Set(activeMounts.map((m) => m.MountPoint));

  const handleAdd = (remote: string, mountPoint: string, vfsMode: "read-only" | "read-write") => {
    addConfig({ remote, mountPoint, vfsMode, autoMount: false });
    mountRemote.mutate({ fs: remote, mountPoint, vfsMode });
  };

  const handleMount = (config: typeof configs[0]) => {
    mountRemote.mutate({
      fs: config.remote,
      mountPoint: config.mountPoint,
      vfsMode: config.vfsMode,
    });
  };

  return (
    <div className="p-6">
      <PageHeader
        title="Mounts"
        description="Mount cloud storage as local drives"
        actions={
          <Button size="sm" onClick={() => setShowAdd(true)}>
            <Plus size={16} className="mr-1" /> Add Mount
          </Button>
        }
      />

      {configs.length === 0 ? (
        <EmptyState
          icon={HardDrive}
          title="No mounts configured"
          description="Mount a remote to access cloud files from your local file system."
          action={
            <Button size="sm" onClick={() => setShowAdd(true)}>
              <Plus size={16} className="mr-1" /> Add Mount
            </Button>
          }
        />
      ) : (
        <div className="mt-4 border border-border rounded-md">
          {configs.map((config) => (
            <MountItem
              key={config.mountPoint}
              config={config}
              isActive={activeMountPoints.has(config.mountPoint)}
              onMount={() => handleMount(config)}
            />
          ))}
        </div>
      )}

      <AddMountDialog
        open={showAdd}
        onClose={() => setShowAdd(false)}
        onAdd={handleAdd}
      />
    </div>
  );
}
```

- [ ] **Step 9: Run all tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: mount manager with add/remove, auto-mount, and VFS modes

Mount store with persistence, mount/unmount via rclone API, add mount
dialog with remote picker and folder browser, active mount polling."
```

---

## Task 11: Settings Page

**Goal:** Build the settings page with theme, rclone config, and transfer settings.

**Files:**
- Create: All files in `src/features/settings/`

- [ ] **Step 1: Create appearance section**

Create `src/features/settings/components/appearance-section.tsx`:

```tsx
import { useTheme } from "../../../app/theme-provider";
import { Label } from "../../../components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../../../components/ui/select";

export function AppearanceSection() {
  const { theme, setTheme } = useTheme();

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium">Appearance</h3>
      <div className="space-y-2">
        <Label>Theme</Label>
        <Select value={theme} onValueChange={setTheme}>
          <SelectTrigger className="w-40">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="light">Light</SelectItem>
            <SelectItem value="dark">Dark</SelectItem>
            <SelectItem value="system">System</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create rclone section**

Create `src/features/settings/components/rclone-section.tsx`:

```tsx
import { useAppStore } from "../../../stores/app-store";
import { Label } from "../../../components/ui/label";
import { Input } from "../../../components/ui/input";

export function RcloneSection() {
  const port = useAppStore((s) => s.rclonePort);
  const binaryPath = useAppStore((s) => s.rcloneBinaryPath);
  const setBinaryPath = useAppStore((s) => s.setRcloneBinaryPath);

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium">Rclone</h3>
      <div className="space-y-2">
        <Label>Daemon Port</Label>
        <Input value={port} disabled className="w-32 font-mono" />
        <p className="text-xs text-muted-foreground">
          Automatically assigned on startup
        </p>
      </div>
      <div className="space-y-2">
        <Label>Binary Path (leave empty for bundled)</Label>
        <Input
          value={binaryPath}
          onChange={(e) => setBinaryPath(e.target.value)}
          placeholder="rclone (uses PATH)"
          className="font-mono text-sm"
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create transfer section**

Create `src/features/settings/components/transfer-section.tsx`:

```tsx
import { useAppStore } from "../../../stores/app-store";
import { Label } from "../../../components/ui/label";
import { Input } from "../../../components/ui/input";

export function TransferSection() {
  const concurrent = useAppStore((s) => s.concurrentTransfers);
  const setConcurrent = useAppStore((s) => s.setConcurrentTransfers);
  const bandwidth = useAppStore((s) => s.bandwidthLimit);
  const setBandwidth = useAppStore((s) => s.setBandwidthLimit);

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium">Transfers</h3>
      <div className="space-y-2">
        <Label>Concurrent Transfers</Label>
        <Input
          type="number"
          min={1}
          max={32}
          value={concurrent}
          onChange={(e) => setConcurrent(Number(e.target.value))}
          className="w-24"
        />
      </div>
      <div className="space-y-2">
        <Label>Bandwidth Limit</Label>
        <Input
          value={bandwidth}
          onChange={(e) => setBandwidth(e.target.value)}
          placeholder="off (e.g. 10M, 1G)"
          className="w-40 font-mono text-sm"
        />
        <p className="text-xs text-muted-foreground">
          Use rclone format: 10M = 10 MB/s, 1G = 1 GB/s, off = unlimited
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Create about section**

Create `src/features/settings/components/about-section.tsx`:

```tsx
export function AboutSection() {
  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium">About</h3>
      <div className="text-sm text-muted-foreground space-y-1">
        <p>StreamCloned v0.1.0</p>
        <p>
          <a
            href="https://github.com/streamcloned/streamcloned"
            target="_blank"
            rel="noopener"
            className="underline hover:text-foreground"
          >
            GitHub
          </a>
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Build the settings page**

Replace `src/features/settings/pages/settings-page.tsx`:

```tsx
import { PageHeader } from "../../../components/page-header";
import { Separator } from "../../../components/ui/separator";
import { AppearanceSection } from "../components/appearance-section";
import { RcloneSection } from "../components/rclone-section";
import { TransferSection } from "../components/transfer-section";
import { AboutSection } from "../components/about-section";

export function SettingsPage() {
  return (
    <div className="p-6 max-w-2xl">
      <PageHeader title="Settings" />
      <div className="mt-6 space-y-6">
        <AppearanceSection />
        <Separator />
        <RcloneSection />
        <Separator />
        <TransferSection />
        <Separator />
        <AboutSection />
      </div>
    </div>
  );
}
```

- [ ] **Step 6: Verify settings page**

```bash
npm run tauri dev
```

Expected: Settings page renders with all sections. Theme switcher works immediately. Form fields update the store.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: settings page with theme, rclone, and transfer config

Appearance (theme switcher), rclone (port display, binary path),
transfers (concurrent count, bandwidth limit), and about section."
```

---

## Task 12: System Tray

**Goal:** Add system tray with mount shortcuts, transfer count, and show/quit actions.

**Files:**
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/commands/rclone.rs` (or create `src-tauri/src/tray.rs`)

- [ ] **Step 1: Enable tray-icon feature in Cargo.toml**

In `src-tauri/Cargo.toml`, ensure the tauri dependency has the `tray-icon` feature:

```toml
tauri = { version = "2", features = ["tray-icon"] }
```

- [ ] **Step 2: Implement system tray setup**

Create `src-tauri/src/tray.rs`:

```rust
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

pub fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "Open StreamCloned", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&show, &separator, &quit])?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "quit" => {
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}
```

- [ ] **Step 3: Register tray in lib.rs**

Add `mod tray;` and call `tray::setup_tray` in the builder:

```rust
mod commands;
mod tray;

use commands::rclone::RcloneState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(RcloneState::default())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            commands::rclone::start_rclone,
            commands::rclone::get_rclone_port,
            commands::rclone::is_rclone_running,
        ])
        .setup(|app| {
            tray::setup_tray(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 4: Verify tray works**

```bash
npm run tauri dev
```

Expected: System tray icon appears. Right-click shows "Open StreamCloned" and "Quit". Clicking tray icon focuses the window.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: system tray with show/quit menu

Left-click focuses window, right-click shows menu with Open and Quit."
```

---

## Task 13: Add Remote Dialog (Provider Picker + Config Form)

**Goal:** Implement the "Add Remote" wizard — provider picker grid, dynamic config form, and OAuth flow handling.

**Files:**
- Create: `src/features/remotes/components/provider-picker.tsx`
- Create: `src/features/remotes/components/config-form.tsx`
- Create: `src/features/remotes/components/add-remote-dialog.tsx`
- Modify: `src/features/remotes/pages/remotes-page.tsx`

- [ ] **Step 1: Create provider picker component**

Create `src/features/remotes/components/provider-picker.tsx`:

```tsx
import { useState } from "react";
import { Input } from "../../../components/ui/input";
import { RemoteIcon } from "../../../components/remote-icon";
import type { Provider } from "../../../lib/rclone/types";

interface ProviderPickerProps {
  providers: Provider[];
  onSelect: (provider: Provider) => void;
}

export function ProviderPicker({ providers, onSelect }: ProviderPickerProps) {
  const [search, setSearch] = useState("");

  const filtered = providers.filter(
    (p) =>
      p.Name.toLowerCase().includes(search.toLowerCase()) ||
      p.Description.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-4">
      <Input
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search providers..."
        autoFocus
      />
      <div className="grid grid-cols-2 gap-2 max-h-80 overflow-y-auto">
        {filtered.map((provider) => (
          <button
            key={provider.Name}
            onClick={() => onSelect(provider)}
            className="flex items-center gap-3 p-3 rounded-md border border-border hover:bg-accent text-left transition-colors"
          >
            <RemoteIcon type={provider.Prefix} size={20} />
            <div className="min-w-0">
              <div className="text-sm font-medium truncate">
                {provider.Description}
              </div>
              <div className="text-xs text-muted-foreground">{provider.Name}</div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create dynamic config form**

Create `src/features/remotes/components/config-form.tsx`:

```tsx
import { useState } from "react";
import { Input } from "../../../components/ui/input";
import { Label } from "../../../components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../../../components/ui/select";
import type { ProviderOption } from "../../../lib/rclone/types";

interface ConfigFormProps {
  options: ProviderOption[];
  values: Record<string, string>;
  onChange: (key: string, value: string) => void;
  showAdvanced?: boolean;
}

export function ConfigForm({
  options,
  values,
  onChange,
  showAdvanced = false,
}: ConfigFormProps) {
  const visibleOptions = options.filter(
    (opt) => !opt.Advanced || showAdvanced
  );

  return (
    <div className="space-y-4">
      {visibleOptions.map((opt) => (
        <div key={opt.Name} className="space-y-1">
          <Label className="text-sm">
            {opt.Name}
            {opt.Required && <span className="text-destructive ml-1">*</span>}
          </Label>
          {opt.Examples && opt.Examples.length > 0 ? (
            <Select
              value={values[opt.Name] ?? ""}
              onValueChange={(v) => onChange(opt.Name, v)}
            >
              <SelectTrigger>
                <SelectValue placeholder={`Select ${opt.Name}`} />
              </SelectTrigger>
              <SelectContent>
                {opt.Examples.map((ex) => (
                  <SelectItem key={ex.Value} value={ex.Value}>
                    {ex.Help || ex.Value}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          ) : (
            <Input
              type={opt.IsPassword ? "password" : "text"}
              value={values[opt.Name] ?? ""}
              onChange={(e) => onChange(opt.Name, e.target.value)}
              placeholder={String(opt.Default ?? "")}
            />
          )}
          {opt.Help && (
            <p className="text-xs text-muted-foreground">{opt.Help}</p>
          )}
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 3: Create add remote dialog**

Create `src/features/remotes/components/add-remote-dialog.tsx`:

```tsx
import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "../../../components/ui/dialog";
import { Button } from "../../../components/ui/button";
import { Input } from "../../../components/ui/input";
import { Label } from "../../../components/ui/label";
import { ProviderPicker } from "./provider-picker";
import { ConfigForm } from "./config-form";
import { useProviders } from "../hooks/use-providers";
import * as remotesApi from "../../../lib/rclone/remotes";
import { useQueryClient } from "@tanstack/react-query";
import type { Provider } from "../../../lib/rclone/types";

interface AddRemoteDialogProps {
  open: boolean;
  onClose: () => void;
}

type Step = "pick-provider" | "configure" | "creating";

export function AddRemoteDialog({ open, onClose }: AddRemoteDialogProps) {
  const { data: providersData } = useProviders();
  const queryClient = useQueryClient();
  const [step, setStep] = useState<Step>("pick-provider");
  const [provider, setProvider] = useState<Provider | null>(null);
  const [name, setName] = useState("");
  const [config, setConfig] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);

  const reset = () => {
    setStep("pick-provider");
    setProvider(null);
    setName("");
    setConfig({});
    setError(null);
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handleProviderSelect = (p: Provider) => {
    setProvider(p);
    setStep("configure");
  };

  const handleCreate = async () => {
    if (!provider || !name) return;
    setStep("creating");
    setError(null);
    try {
      await remotesApi.createRemote(name, provider.Name, config);
      await queryClient.invalidateQueries({ queryKey: ["remotes"] });
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create remote");
      setStep("configure");
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && handleClose()}>
      <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {step === "pick-provider"
              ? "Choose a Provider"
              : `Configure ${provider?.Description}`}
          </DialogTitle>
        </DialogHeader>

        {step === "pick-provider" && providersData && (
          <ProviderPicker
            providers={providersData.providers}
            onSelect={handleProviderSelect}
          />
        )}

        {(step === "configure" || step === "creating") && provider && (
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Remote Name</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="my-remote"
                autoFocus
              />
            </div>
            <ConfigForm
              options={provider.Options}
              values={config}
              onChange={(key, value) =>
                setConfig((prev) => ({ ...prev, [key]: value }))
              }
            />
            {error && (
              <p className="text-sm text-destructive">{error}</p>
            )}
          </div>
        )}

        <DialogFooter>
          {step === "configure" && (
            <>
              <Button variant="outline" onClick={() => setStep("pick-provider")}>
                Back
              </Button>
              <Button
                onClick={handleCreate}
                disabled={!name}
              >
                Create Remote
              </Button>
            </>
          )}
          {step === "creating" && (
            <Button disabled>Creating...</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Wire add dialog into remotes page**

Update `src/features/remotes/pages/remotes-page.tsx` — add state for the dialog and wire the "Add Remote" buttons:

Add import: `import { AddRemoteDialog } from "../components/add-remote-dialog";`

Add state: `const [showAdd, setShowAdd] = useState(false);`

Update the "Add Remote" buttons to: `onClick={() => setShowAdd(true)}`

Add before closing `</div>`: `<AddRemoteDialog open={showAdd} onClose={() => setShowAdd(false)} />`

- [ ] **Step 5: Verify the full add remote flow**

```bash
npm run tauri dev
```

Expected: Click "Add Remote" → provider picker shows with search. Select a provider (e.g., S3 or local) → config form renders dynamic fields. Enter name + config → Create → remote appears in grid.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add remote dialog with provider picker and dynamic config form

Multi-step wizard: search/select provider, dynamic form from
provider Options schema, create remote via rclone API."
```

---

## Task 14: Final Polish & Integration Testing

**Goal:** Wire up any loose ends, ensure all features work end-to-end, and clean up.

**Files:**
- Various small fixes across the codebase

- [ ] **Step 1: Ensure all page exports are correct**

Verify each page component is exported as a named export matching what `router.tsx` imports. Check for any missing exports or typos.

- [ ] **Step 2: Run all tests**

```bash
npm test
```

Expected: All unit tests pass.

- [ ] **Step 3: Run the full app and test each feature**

```bash
npm run tauri dev
```

Test manually:
1. App launches, daemon connects (banner disappears)
2. Remotes page shows configured remotes (or empty state)
3. Add Remote flow works (at least for `local` type)
4. File browser navigates, shows files, breadcrumbs work
5. Copy/Sync page renders, accepts source/destination
6. Transfers page shows transfer history
7. Mounts page allows adding mount configs
8. Settings page — theme switch works
9. System tray shows, menu works

- [ ] **Step 4: Fix any issues found during testing**

Address any compilation errors, broken imports, or UI issues discovered during manual testing.

- [ ] **Step 5: Run Biome lint and format**

```bash
npx biome check --write src/
```

Fix any remaining lint issues.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "chore: polish, lint fixes, and integration verification

All features wired up and manually verified: remotes, browser,
copy/sync, transfers, mounts, settings, system tray."
```

---

## Summary

| Task | Description | Key Deliverable |
|------|-------------|----------------|
| 1 | Project scaffolding | Compiling Tauri + React + TS app with all deps |
| 2 | App shell & routing | Sidebar, theme, stub pages, navigation |
| 3 | Rclone API client | Typed HTTP client for all rclone RC endpoints |
| 4 | Rust backend | Daemon spawn/stop, port detection |
| 5 | Connection banner | Auto-start daemon, status UI |
| 6 | Remote management | Home screen with remote cards, add/delete |
| 7 | File browser | List view, breadcrumbs, file operations |
| 8 | Copy & sync | Source/dest pickers, dry run |
| 9 | Transfer queue | Store, polling, progress, cancel |
| 10 | Mount manager | Mount/unmount, auto-mount, VFS config |
| 11 | Settings | Theme, rclone, transfer config |
| 12 | System tray | Tray icon, menu, show/quit |
| 13 | Add remote dialog | Provider picker, dynamic form, create |
| 14 | Polish & testing | Integration, lint, final fixes |
