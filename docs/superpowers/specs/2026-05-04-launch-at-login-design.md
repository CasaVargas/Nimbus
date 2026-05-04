# Launch at Login — Design

**Date:** 2026-05-04
**Status:** Approved, ready for plan
**Scope:** Both the SwiftUI native app (`Nimbus/`) and the Tauri app (`src-tauri/` + `src/`).

## Problem

Nimbus is a Finder-integration app: File Provider domains and NFS auto-mounts only come up while the app is running. Today the user has to manually open Nimbus before any cloud drives appear in Finder. The ticket asks for the app to start at Mac login and have the File Providers automatically come online.

The auto-mount logic itself already works — `NimbusApp.startApp()` (SwiftUI) and the React `useDaemon` / `useAutoMount` / `useFileProviderSync` hooks (Tauri) already register every File Provider domain and mount every `autoMount: true` NFS config when the app starts. The missing piece is launching the app at login.

## Goals

- A user-controlled "Launch at login" toggle in Settings on both apps.
- When enabled, on macOS login the app starts silently — no window, no Dock bounce — and brings up File Providers and auto-mounts in the background.
- Manual launch (Spotlight, Finder, `open -a`) keeps current behavior: window appears, Dock icon shows.
- The OS is the source of truth for the on/off state (no risk of UI/system drift).

## Non-Goals

- No change to existing auto-mount or File Provider domain registration logic.
- No onboarding prompt asking the user to enable launch at login.
- No notifications when File Providers come online silently.
- No backward compatibility for macOS < 13 (SwiftUI target is 15.0; Tauri target is 13.0; `SMAppService` requires 13+).
- No deprecation work on the Tauri app.

## Architecture

### API choice

Both apps ultimately call **Apple's `SMAppService.mainApp`** (`ServiceManagement` framework, macOS 13+). It registers the app bundle as a Login Item and surfaces in **System Settings → General → Login Items**, which is the standard, user-discoverable place for this.

| App | How it calls SMAppService |
|---|---|
| SwiftUI (`Nimbus/`) | Direct Swift API via `import ServiceManagement`. |
| Tauri | `tauri-plugin-autostart` v2 (official Tauri plugin), which uses `SMAppService` on macOS 13+. |

### Source of truth

`SMAppService.mainApp.status` (Swift) / `isEnabled()` (Tauri plugin) is the single source of truth. The UI toggle is a view + mutation over that state — we **do not** persist a duplicate preference in `UserDefaults` or a Tauri store. This eliminates UI/system drift when the user disables Nimbus from System Settings → Login Items.

### Hidden launch

Both apps detect "this launch was triggered by the OS at login" and respond by suppressing the window and switching to accessory activation policy (no Dock icon).

| App | Detection | Hide mechanism |
|---|---|---|
| SwiftUI | `NSAppleEventManager.shared().currentAppleEvent` → `paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem`, checked in `applicationWillFinishLaunching`. | In `applicationDidFinishLaunching`, `window.orderOut(nil)` + `NSApp.setActivationPolicy(.accessory)`. |
| Tauri | `tauri-plugin-autostart` registers with `args: vec!["--launched-at-login"]`. In `setup`, check `std::env::args()`. | `window.hide()` + `app.set_activation_policy(ActivationPolicy::Accessory)`. |

When the user later clicks the menubar/tray "Show Nimbus":
- SwiftUI: existing menubar action calls `NSApp.activate(ignoringOtherApps: true)` and `makeKeyAndOrderFront`. Augment with `NSApp.setActivationPolicy(.regular)` so the Dock icon comes back.
- Tauri: existing tray action shows the window. Augment with `set_activation_policy(ActivationPolicy::Regular)`.

## Components

### SwiftUI (`Nimbus/`)

#### New file: `Nimbus/Nimbus/Services/LaunchAtLoginService.swift`
`@MainActor @Observable final class`. Wraps `SMAppService.mainApp`. Holds stored state so SwiftUI observation triggers re-renders (`SMAppService` itself is not Observable).

- `private(set) var isEnabled: Bool` — stored; mirrors `SMAppService.mainApp.status == .enabled`. Updated by `refresh()` and after each register/unregister.
- `private(set) var lastError: String?` — localized message from a failed register/unregister, or `nil`.
- `func register()` (non-throwing) — calls `SMAppService.mainApp.register()` inside a `do/catch`; on success sets `isEnabled = true` and clears `lastError`; on failure sets `lastError` and leaves `isEnabled` reflecting the actual `.status`.
- `func unregister() async` (non-throwing) — calls `try await SMAppService.mainApp.unregister()` inside a `do/catch`; same pattern.
- `func refresh()` — re-reads `.status` and updates `isEnabled` (called by Settings on `.onAppear`).
- `init()` — calls `refresh()` so initial UI render is correct.

Logger: `Logger(subsystem: "app.casavargas.nimbus", category: "launchatlogin")`.

#### New file: `Nimbus/Nimbus/Views/Settings/GeneralSection.swift`
SwiftUI `Form` with a single `Toggle("Launch Nimbus at login", isOn: binding)`. The `binding` is a `Binding<Bool>` whose getter returns `service.isEnabled` and whose setter calls `service.register()` (sync) when toggled on or `Task { await service.unregister() }` when toggled off. Below the toggle, conditionally render `Text(lastError).font(.caption).foregroundStyle(.red)` when `service.lastError != nil`. `.onAppear { service.refresh() }`.

#### Modified: `Nimbus/Nimbus/NimbusApp.swift`
- Instantiate `@State private var launchAtLogin = LaunchAtLoginService()`.
- Inject into environment alongside the other services.
- (Activation policy is handled entirely by `AppDelegate`; `NimbusApp` does not duplicate that logic.)

#### Modified: `Nimbus/Nimbus/AppDelegate.swift`
- Add stored `private(set) var wasLaunchedAtLogin: Bool = false`.
- Implement `applicationWillFinishLaunching(_:)` — read `NSAppleEventManager.shared().currentAppleEvent`, set `wasLaunchedAtLogin` accordingly.
- Implement `applicationDidFinishLaunching(_:)` — if `wasLaunchedAtLogin`, call `NSApp.windows.forEach { $0.orderOut(nil) }` and `NSApp.setActivationPolicy(.accessory)`.
- Implement `applicationShouldTerminateAfterLastWindowClosed(_:) -> Bool` returning `false` so closing the window leaves the menubar alive (matches the Tauri app's `prevent_close` behavior).
- The existing menubar "Show Nimbus" action (defined in `NimbusApp.swift`'s `MenuBarExtra`) is augmented to call `NSApp.setActivationPolicy(.regular)` before activating, so the Dock icon returns when the user opens the window after a hidden launch.

#### Modified: `Nimbus/Nimbus/Views/Settings/SettingsView.swift`
Add `GeneralSection()` as the first tab with `Label("General", systemImage: "gearshape")`.

### Tauri (`src-tauri/` + `src/`)

#### New file: `src/hooks/use-launch-at-login.ts`
Wraps `enable`, `disable`, `isEnabled` from `@tauri-apps/plugin-autostart`. Returns `{ enabled: boolean, toggle: () => Promise<void>, error: string | null, refresh: () => Promise<void> }`. Re-queries `isEnabled()` on the component's mount via the consumer's `useEffect`.

#### New file: `src/features/settings/components/general-section.tsx`
shadcn `Switch` + `Label` matching the visual style of `appearance-section.tsx`. Below the switch, `<p className="text-xs text-destructive">{error}</p>` when present. Calls `refresh()` on mount.

#### Modified: `src-tauri/Cargo.toml`
Add `tauri-plugin-autostart = "2"`.

#### Modified: `src-tauri/src/lib.rs`
- `.plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec!["--launched-at-login"])))`.
- In `setup`: check `std::env::args().any(|a| a == "--launched-at-login")`. If true, get the main window and `.hide()`, plus `app.set_activation_policy(tauri::ActivationPolicy::Accessory)`. Otherwise leave existing show behavior alone.

#### Modified: `src-tauri/capabilities/default.json` (or matching capability file)
Grant `autostart:default` permission.

#### Modified: `package.json`
Add `@tauri-apps/plugin-autostart` (matching v2 of the Rust crate).

#### Modified: `src/features/settings/pages/settings-page.tsx`
Add General tab as the first tab.

#### Modified: `src-tauri/src/tray.rs` (only if needed)
Ensure tray "Show" action calls `app.set_activation_policy(Regular)` before `window.show()`. If the existing implementation already does the equivalent, leave it.

## Data Flow

### Enable flow (user toggles ON)

```
User flips toggle in Settings
  ↓
SwiftUI: LaunchAtLoginService.register() → SMAppService.mainApp.register()
Tauri:   useLaunchAtLogin.toggle()       → @tauri-apps/plugin-autostart enable()
  ↓
macOS registers Login Item (visible in System Settings → General → Login Items)
  ↓
On next login: launchd starts the app with the registered args
  ↓
App detects login launch (NSAppleEventManager / --launched-at-login arg)
  ↓
App suppresses window, sets accessory policy
  ↓
Existing startup runs: rclone daemon → File Provider domains → NFS auto-mounts
  ↓
Menubar/tray icon visible; Finder shows cloud drives within seconds
```

### Disable flow

User flips toggle off → `unregister()` / `disable()` → SMAppService removes the Login Item → next login, app does not start.

User can also disable from System Settings → General → Login Items. Our toggle reflects the OS state on next `refresh()` (called when the Settings window/page mounts).

## Error Handling

| Failure | Behavior |
|---|---|
| App not in `/Applications` (or `~/Applications`) at registration time | `register()` throws. Toggle stays off. Caption shows: "Move Nimbus to your Applications folder to enable launch at login." |
| User denied login items in System Settings | Same caption pattern, message reflects the localized error from `SMAppServiceErrorDomain`. |
| rclone daemon fails during silent login launch | Swallowed silently per existing `startApp()` behavior (`try?`). User sees no toast. Opens window via menubar → existing connection banner shows the failure. |
| File Provider domain registration fails for one remote | Existing non-fatal handling preserved. |
| NFS auto-mount fails | Existing `try?` swallow preserved. Health monitor continues to run. |

We do **not** poll `SMAppService.status`; we refresh on Settings mount only.

## Testing

### SwiftUI

- **Manual:** toggle ON in Settings → quit Nimbus → log out and log back in → confirm menubar icon appears, no window pops, Finder sidebar shows File Provider entries.
- **Manual:** toggle ON → reopen via menubar → verify window appears and Dock icon returns.
- **Manual:** disable from System Settings → Login Items → reopen Nimbus Settings → confirm toggle reflects off state on `.onAppear`.
- **Manual:** run app from `~/Downloads` → toggle ON → confirm error caption and toggle stays off.
- **Visual verification:** use Apple Xcode MCP `RenderPreview` on `GeneralSection` previews (one with no error, one with error caption).

### Tauri

- **Manual:** same matrix as SwiftUI (login cycle, menubar reopen, System Settings disable, location-based failure).
- **Unit:** none new — the hook is a thin wrapper.

### Both

- **Smoke:** confirm `auto-mount` and File Provider domains come up identically whether app is launched manually or at login (existing `startApp()` runs unchanged).

## Build Sequence

1. **SwiftUI side**
   1. Add `LaunchAtLoginService.swift`, `GeneralSection.swift`.
   2. Modify `NimbusApp.swift`, `AppDelegate.swift`, `SettingsView.swift`.
   3. `cd Nimbus && xcodegen generate`.
   4. Build with XcodeBuildMCP `build_sim` (or `build_device` for real login test).
   5. Manual login-cycle smoke test.

2. **Tauri side** (independent of SwiftUI work)
   1. Add `tauri-plugin-autostart` to `Cargo.toml` and `package.json`.
   2. Modify `lib.rs` to register plugin with launch arg + handle hidden start.
   3. Add capability permission.
   4. Add `use-launch-at-login.ts` hook and `general-section.tsx` component.
   5. Wire General tab into `settings-page.tsx`.
   6. `npm run dev` for dev verification, then `npm run build && cargo tauri build`.
   7. Manual login-cycle smoke test from a `.app` installed in `/Applications`.

The two apps can be implemented in parallel — they share no files.

## Open questions

None at design time. Implementation may surface tray-policy timing details on the Tauri side; resolved at build time, not blocking the design.
