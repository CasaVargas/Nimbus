# Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Launch at login" toggle to both the SwiftUI native app and the Tauri app so Nimbus starts automatically on macOS login, hidden, with File Provider domains and NFS auto-mounts coming online silently.

**Architecture:** Both apps call Apple's `SMAppService.mainApp` (macOS 13+). SwiftUI calls it directly via `ServiceManagement`; Tauri uses `tauri-plugin-autostart` (which wraps `SMAppService` on macOS). The OS is the source of truth — no persisted preference of our own. Login launches are detected (Carbon AE on Swift, custom launch arg on Tauri) and trigger `orderOut`/`hide` + accessory activation policy so the window and Dock icon stay hidden until the user opens via menubar/tray.

**Tech Stack:**
- SwiftUI: `ServiceManagement.SMAppService`, `NSAppleEventManager`, `@MainActor @Observable`
- Tauri: `tauri-plugin-autostart` v2 (Rust + JS), shadcn `Switch`
- Build tools: XcodeGen, XcodeBuildMCP, Vite, cargo

**Spec:** `docs/superpowers/specs/2026-05-04-launch-at-login-design.md`

**Order:** SwiftUI tasks (1–7) first because the user prioritizes the native app per CLAUDE.md, then Tauri tasks (8–14). The two apps share zero files, so they're independent — Tauri can be done first if preferred.

---

## SwiftUI App (`Nimbus/`)

### Task 1: Create `LaunchAtLoginService`

**Files:**
- Create: `Nimbus/Nimbus/Services/LaunchAtLoginService.swift`

- [ ] **Step 1: Write the service**

```swift
import Foundation
import Observation
import os
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "app.casavargas.nimbus", category: "launchatlogin")

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
        logger.info("Launch-at-login status refreshed: \(self.isEnabled)")
    }

    func register() {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
            lastError = nil
            logger.info("Registered as login item")
        } catch {
            lastError = Self.message(for: error)
            isEnabled = SMAppService.mainApp.status == .enabled
            logger.error("Register failed: \(error.localizedDescription)")
        }
    }

    func unregister() async {
        do {
            try await SMAppService.mainApp.unregister()
            isEnabled = false
            lastError = nil
            logger.info("Unregistered as login item")
        } catch {
            lastError = Self.message(for: error)
            isEnabled = SMAppService.mainApp.status == .enabled
            logger.error("Unregister failed: \(error.localizedDescription)")
        }
    }

    /// Maps known SMAppService failures to user-facing strings.
    /// SMAppService.mainApp.register() refuses to register when the bundle
    /// isn't in /Applications or ~/Applications, so we check that condition
    /// directly and surface a precise hint.
    private static func message(for error: Error) -> String {
        if !isInApplicationsFolder() {
            return "Move Nimbus to your Applications folder, then try again."
        }
        return error.localizedDescription
    }

    private static func isInApplicationsFolder() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix("\(NSHomeDirectory())/Applications/")
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `cd Nimbus && xcodegen generate`
Expected: "Created project at Nimbus.xcodeproj"

- [ ] **Step 3: Build to verify it compiles**

Use XcodeBuildMCP `build_sim` (or `build_macos`) on scheme `Nimbus`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/Services/LaunchAtLoginService.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add LaunchAtLoginService wrapping SMAppService"
```

---

### Task 2: Add login-launch detection to `AppDelegate`

**Files:**
- Modify: `Nimbus/Nimbus/AppDelegate.swift`

- [ ] **Step 1: Replace the file with the updated implementation**

```swift
import AppKit
import Carbon.AE  // for keyAEPropData / keyAELaunchedAsLogInItem

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when launchd started us at login (vs. user-initiated launch).
    /// Read once in applicationWillFinishLaunching.
    private(set) var wasLaunchedAtLogin: Bool = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           let propData = event.paramDescriptor(forKeyword: keyAEPropData),
           propData.enumCodeValue == keyAELaunchedAsLogInItem {
            wasLaunchedAtLogin = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if wasLaunchedAtLogin {
            // Hide all windows and become an accessory app (no Dock icon).
            for window in NSApp.windows {
                window.orderOut(nil)
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Closing the only window must NOT terminate the app — we want the
    /// MenuBarExtra to keep running so the user can reopen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Bring back the Dock icon when reopening from Finder/Spotlight.
            NSApp.setActivationPolicy(.regular)
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Use XcodeBuildMCP `build_macos` on scheme `Nimbus`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/AppDelegate.swift
git commit -m "feat(swiftui): detect login-launch and suppress window in AppDelegate"
```

---

### Task 3: Update menubar action to restore Dock icon

**Files:**
- Modify: `Nimbus/Nimbus/NimbusApp.swift`

The existing `MenuBarExtra` "Show Nimbus" button needs to flip activation policy back to `.regular` before bringing the window forward, otherwise after a hidden launch the Dock icon won't reappear.

- [ ] **Step 1: Replace the `MenuBarExtra` block**

Locate this block in `NimbusApp.swift`:

```swift
MenuBarExtra("Nimbus", systemImage: "cloud") {
    Button("Show Nimbus") {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    Divider()
    Button("Quit") {
        Task {
            await shutdown()
            NSApp.terminate(nil)
        }
    }
}
```

Replace it with:

```swift
MenuBarExtra("Nimbus", systemImage: "cloud") {
    Button("Show Nimbus") {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    Divider()
    Button("Quit") {
        Task {
            await shutdown()
            NSApp.terminate(nil)
        }
    }
}
```

(`canBecomeMain` filter avoids accidentally targeting the menubar's hidden helper window.)

- [ ] **Step 2: Inject `LaunchAtLoginService` into the environment**

In the same file, add a `@State` and an `.environment(...)` modifier. Locate the existing block:

```swift
@State private var bookmarkStore = BookmarkStore()
```

Add immediately after it:

```swift
@State private var launchAtLogin = LaunchAtLoginService()
```

Locate the `.environment(bookmarkStore)` line and add immediately after it:

```swift
.environment(launchAtLogin)
```

- [ ] **Step 3: Build to verify it compiles**

Use XcodeBuildMCP `build_macos`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Nimbus/Nimbus/NimbusApp.swift
git commit -m "feat(swiftui): restore Dock icon on menubar reopen and inject LaunchAtLoginService"
```

---

### Task 4: Create `GeneralSection` view

**Files:**
- Create: `Nimbus/Nimbus/Views/Settings/GeneralSection.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

struct GeneralSection: View {
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        Form {
            Toggle("Launch Nimbus at login", isOn: launchAtLoginBinding)
            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { launchAtLogin.refresh() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { newValue in
                if newValue {
                    launchAtLogin.register()
                } else {
                    Task { await launchAtLogin.unregister() }
                }
            }
        )
    }
}

#Preview("Idle") {
    GeneralSection()
        .environment(LaunchAtLoginService())
        .frame(width: 450, height: 250)
        .padding()
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `cd Nimbus && xcodegen generate`
Expected: project regenerated.

- [ ] **Step 3: Render the preview to visually verify layout**

Use Apple Xcode MCP `RenderPreview` on `GeneralSection` preview "Idle".
Expected: a Settings-style form with one toggle labeled "Launch Nimbus at login", no error text.

If layout is broken, fix and re-render before continuing.

- [ ] **Step 4: Build to verify it compiles**

Use XcodeBuildMCP `build_macos`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/Settings/GeneralSection.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add GeneralSection with launch-at-login toggle"
```

---

### Task 5: Wire `GeneralSection` into Settings as the first tab

**Files:**
- Modify: `Nimbus/Nimbus/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add the `general` case to `SettingsTab`**

Locate:

```swift
enum SettingsTab: Hashable {
    case appearance, transfers, rclone, storage, about
}
```

Replace with:

```swift
enum SettingsTab: Hashable {
    case general, appearance, transfers, rclone, storage, about
}
```

- [ ] **Step 2: Change the default selected tab and prepend the General tab**

Locate:

```swift
@State private var selectedTab: SettingsTab = .appearance

var body: some View {
    TabView(selection: $selectedTab) {
        AppearanceSection()
            .tag(SettingsTab.appearance)
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
```

Replace with:

```swift
@State private var selectedTab: SettingsTab = .general

var body: some View {
    TabView(selection: $selectedTab) {
        GeneralSection()
            .tag(SettingsTab.general)
            .tabItem { Label("General", systemImage: "gearshape") }

        AppearanceSection()
            .tag(SettingsTab.appearance)
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
```

- [ ] **Step 3: Inject `LaunchAtLoginService` into the Settings scene**

Open `Nimbus/Nimbus/NimbusApp.swift` and locate the `Settings` scene block:

```swift
Settings {
    SettingsView()
        .environment(settings)
        .environment(daemon)
}
```

Replace with:

```swift
Settings {
    SettingsView()
        .environment(settings)
        .environment(daemon)
        .environment(launchAtLogin)
}
```

- [ ] **Step 4: Build to verify it compiles**

Use XcodeBuildMCP `build_macos`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/Settings/SettingsView.swift Nimbus/Nimbus/NimbusApp.swift
git commit -m "feat(swiftui): wire GeneralSection as first Settings tab"
```

---

### Task 6: Visual verification of full Settings UI

- [ ] **Step 1: Render the SettingsView preview**

Use Apple Xcode MCP `RenderPreview` on `SettingsView` if a preview exists; otherwise build, run, and open Settings via `Cmd+,`.

Expected: the General tab is selected by default, shows the "Launch Nimbus at login" toggle, and the existing tabs (Appearance, Transfers, Rclone, Storage, About) all still render.

- [ ] **Step 2: Verify the toggle reflects current OS state**

Run the app from `/Applications/Nimbus.app` (drag the built `.app` there if it isn't already). Open Settings → General. Toggle the switch ON. Open **System Settings → General → Login Items** and confirm "Nimbus" appears under "Open at Login" with the switch ON.

Toggle OFF in Nimbus → re-check System Settings → entry is gone.

If running from `~/Downloads` or anywhere outside `/Applications`, the toggle should fail and surface the "Move Nimbus to your Applications folder" caption.

- [ ] **Step 3: No commit needed** (verification only).

---

### Task 7: Login-cycle smoke test (SwiftUI)

This is a manual end-to-end test. Skipping it leaves the feature unverified.

- [ ] **Step 1: Build and install a release-style binary**

Build with XcodeBuildMCP `build_macos` (Release configuration), drag the `.app` to `/Applications`.

- [ ] **Step 2: Enable launch-at-login**

Launch Nimbus from `/Applications`, open Settings → General, toggle "Launch Nimbus at login" ON. Quit Nimbus (`Cmd+Q`).

- [ ] **Step 3: Log out and log back in**

Use Apple menu → Log Out (or restart). Log in with the same user account.

- [ ] **Step 4: Verify hidden launch behavior**

Expected:
- No window appears.
- No Dock bounce, no Dock icon.
- The cloud menubar icon is visible.
- Within 5–10 seconds, Finder's sidebar shows the configured cloud remotes as File Provider entries.
- Any `MountConfig` entries with `autoMount == true` show up as mounted volumes.

- [ ] **Step 5: Verify reopen from menubar**

Click the cloud menubar icon → "Show Nimbus". Expected: window appears, Dock icon returns.

- [ ] **Step 6: Verify disable from System Settings**

Open System Settings → General → Login Items, toggle Nimbus OFF. Open Nimbus Settings → General. Expected: the in-app toggle reflects OFF (after `.onAppear` refresh).

- [ ] **Step 7: No commit needed** (verification only).

If any step fails, debug before moving on. Common failures:
- Window pops up on login → `wasLaunchedAtLogin` detection failed; check `Console.app` for "launchatlogin" subsystem messages.
- File Providers don't appear → confirm `startApp()` runs (it should — login launch doesn't change scene phases).

---

## Tauri App (`src-tauri/` + `src/`)

### Task 8: Add `tauri-plugin-autostart` dependency

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Modify: `package.json`
- Modify: `src-tauri/capabilities/default.json`

- [ ] **Step 1: Add the Rust crate**

In `src-tauri/Cargo.toml`, locate the `[dependencies]` block and add a line:

```toml
tauri-plugin-autostart = "2"
```

The `[dependencies]` section should now include (among existing entries):

```toml
tauri-plugin-notification = "2.3.3"
tauri-plugin-autostart = "2"
tokio = { version = "1", features = ["time"] }
```

- [ ] **Step 2: Add the JS package**

Run: `npm install @tauri-apps/plugin-autostart`
Expected: package added; `package.json` `dependencies` now includes `"@tauri-apps/plugin-autostart": "^2..."`.

- [ ] **Step 3: Grant the capability**

In `src-tauri/capabilities/default.json`, append `"autostart:default"` to the `permissions` array:

```json
{
  "identifier": "default",
  "description": "Default permissions for Nimbus",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "shell:allow-execute",
    "shell:allow-spawn",
    "shell:allow-open",
    "dialog:allow-open",
    "dialog:allow-save",
    "dialog:allow-message",
    "dialog:allow-ask",
    "store:default",
    "http:default",
    "notification:default",
    "opener:default",
    "os:default",
    "autostart:default"
  ]
}
```

- [ ] **Step 4: Verify the Rust crate compiles**

Run: `cd src-tauri && cargo check`
Expected: `Finished` with no errors. (Will pull tauri-plugin-autostart on first run.)

- [ ] **Step 5: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock package.json package-lock.json src-tauri/capabilities/default.json
git commit -m "feat(tauri): add tauri-plugin-autostart dependency and capability"
```

---

### Task 9: Register plugin and handle hidden launch in `lib.rs`

**Files:**
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Register the plugin and add hidden-launch handling**

Locate the existing `tauri::Builder::default()` chain and the `.setup(|app| { ... })` block.

Add the plugin registration alongside the other `.plugin(...)` calls. Place it between `tauri_plugin_os::init()` and `.invoke_handler`:

```rust
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--launched-at-login"]),
        ))
        .invoke_handler(tauri::generate_handler![
```

In the `.setup(|app| { ... })` closure, add the hidden-launch handling at the very top (before the existing stale-mount cleanup):

```rust
        .setup(|app| {
            // If launchd started us at login, hide the window and switch to
            // accessory activation policy so we behave like a menubar app.
            let launched_at_login = std::env::args().any(|a| a == "--launched-at-login");
            if launched_at_login {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.hide();
                }
                #[cfg(target_os = "macos")]
                {
                    use tauri::ActivationPolicy;
                    let _ = app.set_activation_policy(ActivationPolicy::Accessory);
                }
            }

            tray::setup_tray(app)?;
```

(The rest of the existing `setup` body — stale mount cleanup, health monitor — stays unchanged.)

- [ ] **Step 2: Verify `tauri::Manager` is in scope for `set_activation_policy`**

The file already has `use tauri::Manager;`. `set_activation_policy` is on the `App` value directly, no extra import needed.

- [ ] **Step 3: Build to verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: `Finished` with no errors.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/lib.rs
git commit -m "feat(tauri): register autostart plugin and handle hidden launch"
```

---

### Task 10: Restore activation policy on tray reopen

**Files:**
- Modify: `src-tauri/src/tray.rs`

After a hidden login launch, the app is in `.accessory` policy. Clicking the tray to show the window must flip back to `.regular` so the Dock icon returns.

- [ ] **Step 1: Add a small helper and use it in both reopen paths**

At the top of the file, add an import:

```rust
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};
```

Add this helper at the bottom of the file:

```rust
fn show_main_window(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    {
        use tauri::ActivationPolicy;
        let _ = app.set_activation_policy(ActivationPolicy::Regular);
    }
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}
```

Replace the menu "show" handler:

```rust
            "show" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
```

with:

```rust
            "show" => {
                show_main_window(app);
            }
```

Replace the tray-icon click handler body:

```rust
                let app = tray.app_handle();
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
```

with:

```rust
                show_main_window(tray.app_handle());
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: `Finished` with no errors.

- [ ] **Step 3: Commit**

```bash
git add src-tauri/src/tray.rs
git commit -m "feat(tauri): restore Regular activation policy on tray reopen"
```

---

### Task 11: Add shadcn `Switch` component

**Files:**
- Create: `src/components/ui/switch.tsx` (via shadcn CLI)

- [ ] **Step 1: Add the component**

Run: `npx shadcn@latest add switch`
Expected: `src/components/ui/switch.tsx` created.

- [ ] **Step 2: Verify Biome formatting passes**

Run: `npx biome check src/components/ui/switch.tsx`
Expected: no errors. If formatting is off, run `npx biome check --apply src/components/ui/switch.tsx`.

- [ ] **Step 3: Commit**

```bash
git add src/components/ui/switch.tsx package.json package-lock.json
git commit -m "chore(tauri): add shadcn Switch component"
```

---

### Task 12: Create `useLaunchAtLogin` hook

**Files:**
- Create: `src/hooks/use-launch-at-login.ts`

- [ ] **Step 1: Write the hook**

```typescript
import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
import { useCallback, useEffect, useState } from "react";

interface LaunchAtLoginState {
  enabled: boolean;
  loading: boolean;
  error: string | null;
  toggle: () => Promise<void>;
  refresh: () => Promise<void>;
}

export function useLaunchAtLogin(): LaunchAtLoginState {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const value = await isEnabled();
      setEnabled(value);
      setError(null);
    } catch (err) {
      setError(formatError(err));
    } finally {
      setLoading(false);
    }
  }, []);

  const toggle = useCallback(async () => {
    setLoading(true);
    try {
      if (enabled) {
        await disable();
        setEnabled(false);
      } else {
        await enable();
        setEnabled(true);
      }
      setError(null);
    } catch (err) {
      setError(formatError(err));
      // Re-sync to whatever the OS actually has.
      await refresh();
    } finally {
      setLoading(false);
    }
  }, [enabled, refresh]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { enabled, loading, error, toggle, refresh };
}

function formatError(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err);
  // The plugin's failure modes on macOS are dominated by "app not in
  // /Applications". Append a hint rather than try to pattern-match the
  // underlying error string, which varies across macOS versions.
  return `${message} (If this fails repeatedly, ensure Nimbus is in your Applications folder.)`;
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Verify Biome passes**

Run: `npx biome check src/hooks/use-launch-at-login.ts`
Expected: no errors. Apply with `--apply` if needed.

- [ ] **Step 4: Commit**

```bash
git add src/hooks/use-launch-at-login.ts
git commit -m "feat(tauri): add useLaunchAtLogin hook wrapping plugin-autostart"
```

---

### Task 13: Create `GeneralSection` component and wire into Settings page

**Files:**
- Create: `src/features/settings/components/general-section.tsx`
- Modify: `src/features/settings/pages/settings-page.tsx`

- [ ] **Step 1: Write the component**

```tsx
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { useLaunchAtLogin } from "@/hooks/use-launch-at-login";

export function GeneralSection() {
  const { enabled, loading, error, toggle } = useLaunchAtLogin();

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">General</h3>
        <p className="text-xs text-muted-foreground">
          Startup and system integration.
        </p>
      </div>
      <div className="flex items-center gap-3">
        <Switch
          id="launch-at-login"
          checked={enabled}
          disabled={loading}
          onCheckedChange={() => {
            void toggle();
          }}
        />
        <Label htmlFor="launch-at-login">Launch Nimbus at login</Label>
      </div>
      {error && (
        <p className="text-xs text-destructive">{error}</p>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Add the section to the settings page as the first section**

Replace the contents of `src/features/settings/pages/settings-page.tsx`:

```tsx
import { PageHeader } from "@/components/page-header";
import { Separator } from "@/components/ui/separator";
import { AboutSection } from "../components/about-section";
import { AppearanceSection } from "../components/appearance-section";
import { GeneralSection } from "../components/general-section";
import { RcloneSection } from "../components/rclone-section";
import { StorageUsage } from "../components/storage-usage";
import { TransferSection } from "../components/transfer-section";

export default function SettingsPage() {
  return (
    <div>
      <PageHeader title="Settings" description="Configure Nimbus preferences" />
      <div className="space-y-6 p-6">
        <GeneralSection />
        <Separator />
        <AppearanceSection />
        <Separator />
        <RcloneSection />
        <Separator />
        <TransferSection />
        <Separator />
        <StorageUsage />
        <Separator />
        <AboutSection />
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Verify Biome passes**

Run: `npx biome check src/features/settings/`
Expected: no errors. Apply with `--apply` if needed.

- [ ] **Step 5: Run frontend tests**

Run: `npm run test`
Expected: existing tests pass; no new failures.

- [ ] **Step 6: Visual verification in dev mode**

Run: `npm run dev` (in one terminal) and `npm run tauri dev` if needed.
Open the app → Settings page → confirm the new "General" section appears at the top with a working-looking switch.

- [ ] **Step 7: Commit**

```bash
git add src/features/settings/components/general-section.tsx src/features/settings/pages/settings-page.tsx
git commit -m "feat(tauri): add General settings section with launch-at-login toggle"
```

---

### Task 14: Login-cycle smoke test (Tauri)

- [ ] **Step 1: Build a release binary**

Run: `bash scripts/build-release.sh`
Expected: app bundle produced under `src-tauri/target/release/bundle/macos/Nimbus.app`.

- [ ] **Step 2: Install to `/Applications`**

Drag (or `cp -R`) the `.app` to `/Applications`. (Required for `SMAppService.mainApp` to register.)

- [ ] **Step 3: Enable launch-at-login**

Launch Nimbus from `/Applications`, open Settings → General section, flip the switch ON. Confirm in System Settings → General → Login Items that "Nimbus" now appears with its switch ON. Quit Nimbus.

- [ ] **Step 4: Log out and log back in**

Apple menu → Log Out (or restart). Log in.

- [ ] **Step 5: Verify hidden launch behavior**

Expected:
- No window appears.
- No Dock bounce, no Dock icon.
- The Nimbus tray icon is visible.
- Within 5–10 seconds, Finder shows configured cloud remotes as File Provider entries (driven by the existing `useFileProviderSync` hook).
- `autoMount: true` configs become mounted volumes.

- [ ] **Step 6: Verify reopen from tray**

Click the tray icon (or use the menu's "Open Nimbus") → window appears, Dock icon returns.

- [ ] **Step 7: Verify disable from System Settings**

Toggle Nimbus OFF in System Settings → Login Items. Reopen Nimbus settings page → confirm switch reflects OFF (driven by the hook's `useEffect`/`refresh`).

- [ ] **Step 8: No commit needed** (verification only).

If hidden launch fails: confirm the `--launched-at-login` arg is actually being passed by the LaunchAgent. Inspect `~/Library/LaunchAgents/app.casavargas.nimbus.plist` (the plugin writes one) and verify the `ProgramArguments` array includes `"--launched-at-login"`.

---

## Final Sign-Off

- [ ] **Step 1: Confirm both apps work**

Both Task 7 (SwiftUI smoke) and Task 14 (Tauri smoke) passed end-to-end.

- [ ] **Step 2: No leftover changes**

Run: `git status`
Expected: clean working tree.

- [ ] **Step 3: Update spec status if needed**

If any deviation from the spec emerged during implementation, append a short "Implementation notes" section to `docs/superpowers/specs/2026-05-04-launch-at-login-design.md` documenting it, and commit:

```bash
git add docs/superpowers/specs/2026-05-04-launch-at-login-design.md
git commit -m "docs: implementation notes for launch-at-login"
```
