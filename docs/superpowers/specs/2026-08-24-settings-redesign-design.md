# Nimbus Settings Redesign

**Date:** 2026-08-24
**Status:** Approved design
**Scope:** Reorganize Nimbus Settings into three focused panes and add curated global defaults backed by real application behavior.

## Objective

Nimbus Settings should feel like a compact native macOS preferences window rather than six equally weighted destinations with sparse content. Everyday preferences must be easy to find, operational rclone details must stay out of the main path, and every new preference must affect real behavior.

The redesign has four goals:

1. Reduce navigation from six toolbar panes to three coherent panes.
2. Add practical defaults for future remotes, mounts, and transfers.
3. Preserve every existing remote and mount configuration when global defaults change.
4. Make operational failures visible and recoverable without exposing credentials or user file data.

## Non-Goals

- Rewriting existing remote or mount configurations when a default changes.
- Exposing raw rclone, VFS, retry, or performance flags as general preferences.
- Adding a cache-size limit before Nimbus has a reliable eviction policy.
- Allowing the menu-bar item to be disabled. Nimbus relies on it to reopen after the final window closes.
- Cloud-syncing preferences or transfer history.
- Adding a reset-all action.

## Information Architecture

Keep the native macOS toolbar-style TabView, but reduce it to:

1. **General** — application behavior, appearance, defaults for future Finder integration and mounts, local storage, and About.
2. **Transfers** — performance, conflict behavior, notifications, and history retention.
3. **Advanced** — rclone binary, daemon status/actions, and privacy-safe diagnostics.

The Settings window uses a 680 × 520 point default size. Each pane owns its internal scrolling if its content cannot fit at large accessibility text sizes. Controls use native SwiftUI pickers, switches, steppers, text fields, buttons, and links. Values save immediately; there is no Apply button.

## General Pane

### Application

- **Launch at Login** — existing LaunchAtLoginService switch.
- **Appearance** — menu picker with System, Light, and Dark.

The menu-bar item remains permanently enabled because it is Nimbus's reliable reopen path after the last main window closes.

### Finder

- **Add New Remotes to Finder** — Boolean, default true.
- **New Mount Access** — Read & Write or Read Only, default Read & Write.
- **Mount New Volumes at Login** — Boolean, default false.

A caption states that these are defaults for configurations created later. Changing them never mutates an existing File Provider domain or MountConfig.

Both manually added and imported remotes count as new remotes. When the Finder default is enabled, Nimbus attempts to register the new File Provider domain after remote creation succeeds.

### Local Storage

- **Cached Locally** — best-effort current byte count.
- **Clear Cache…** — destructive button with confirmation.

No cache-size limit ships in this scope. Nimbus does not yet own an eviction system capable of enforcing one honestly.

### About

- Nimbus app icon and version/build.
- “© 2026 CasaVargas LLC”.
- Link to rclone.

About becomes a compact section in General rather than a top-level destination.

## Transfers Pane

### Performance

- **Concurrent Transfers** — integer stepper, range 1 through 32, default 4.
- **Bandwidth Limit** — rclone-compatible value, default unlimited.

Bandwidth validation accepts an empty value or a positive number with a supported k, M, G, or T suffix. Invalid drafts do not replace the last valid persisted value. The field commits on Return or focus loss.

On a valid commit, Nimbus applies the value to the connected daemon first through
`core/bwlimit`, then persists it only after rclone accepts the request. An empty
preference is sent as rclone's `off` rate and persisted as an empty value. If the
RC request fails, Nimbus leaves both the persisted preference and the active
daemon setting at their prior values and shows a nonmodal inline error.

Concurrent Transfers uses rclone's live `options/set` endpoint with
`{"main":{"Transfers":count}}`. Nimbus persists the count only after that RC
request succeeds. The option controls operations started after the update;
existing jobs keep the concurrency they started with. Every daemon launch and
retry also receives the persisted `--transfers` value and explicit `--bwlimit`
value (`off` for unlimited), so a reconnect preserves the accepted settings.

### Behavior

- **File Conflicts** — Rename, Skip, or Overwrite; default Rename.
- **Transfer Notifications** — Failures Only, All Transfers, or Off; default Failures Only.
- **Keep Transfer History** — 7 Days, 30 Days, Forever, or Until Nimbus Quits; default 7 Days.

The conflict preference initializes new copy confirmations. Users can override it for each operation. The effective per-operation choice always wins.

Notification permission is requested only when the selected mode first requires notifications. Failures Only notifies on failed transfers, All Transfers notifies on completed and failed transfers, and Off sends none. Cancelled jobs do not notify.

## Advanced Pane

### Rclone

- Binary path with Choose and Reveal actions.
- Detected rclone version.

Changing the binary path does not restart the daemon automatically. The pane displays **Restart Required** and offers **Restart Now** so active transfers are not interrupted without an explicit action.

### Daemon

- Current status.
- Active port.
- Restart action.

Restart uses a first-class RcloneDaemon API. A failed restart remains visible through the daemon's standard error state and exposes Retry.

### Diagnostics

- **Open Logs in Console** scoped to Nimbus's logging subsystem.
- **Copy System Information** containing Nimbus version/build, macOS version, architecture, rclone version, daemon status, and daemon port.

Diagnostics must not include rclone configuration, credentials, remote names, local or remote paths, or filenames.

## State Ownership

AppSettings continues to own lightweight preferences persisted in UserDefaults:

- appearance
- concurrent transfer count
- bandwidth limit
- add-new-remotes-to-Finder default
- new-mount access default
- new-mount auto-mount default
- default conflict policy
- transfer notification mode
- transfer-history retention

Each enum uses a stable raw string representation. Tests use injected, isolated UserDefaults suites rather than UserDefaults.standard.

Transfer history is not a preference value and does not belong in UserDefaults. TransferStore owns a versioned Application Support file named transfer-history-v1.json. The format stores only finished transfer records required by the Transfers UI.

## Application Points

Defaults are read only at creation boundaries:

- AddRemoteSheet and ImportConfigSheet apply the Finder integration default after rclone remote creation succeeds.
- AddMountSheet initializes access and auto-mount state from AppSettings only when creating a mount. Edit mode initializes from the existing MountConfig.
- Every new CopyRequest initializes its conflict policy from AppSettings.
- Transfer state transitions consult the notification policy and persist eligible history records.

Existing remote domains, disabled-domain choices, and mount configurations remain authoritative and unchanged.

## Transfer History

TransferStore persists completed, failed, and cancelled transfers. Active jobs are never written as resumable state and are never resurrected on launch.

Persistence behavior:

1. Load the versioned JSON file during application bootstrap.
2. If retention is Until Nimbus Quits, do not load or write finished history.
3. Prune expired records after load, after a transfer finishes, and when retention changes.
4. Write atomically after a finished transfer changes, is removed, or completed history is cleared.
5. Preserve Forever records until the user removes or clears them.

If decoding fails, move the unreadable file beside the original with a timestamped .corrupt suffix, log the recovery, and continue with empty history.

## Notification Service

A focused notification service wraps UNUserNotificationCenter behind an injectable protocol. TransferStore reports terminal transfer transitions to the service; views do not send notifications.

If authorization is denied, retain the selected preference but display “Disabled in System Settings” with an action that opens the app's notification settings. This makes the desired policy visible without pretending notifications are currently deliverable.

## Error Handling

- **Remote created, Finder registration fails:** keep the remote, show a non-blocking warning, and offer Retry Finder Integration. Never roll back the cloud configuration.
- **Invalid bandwidth:** retain the draft and show inline validation; keep the last valid persisted value.
- **Live transfer setting apply fails:** retain the last persisted daemon-accepted value and show a nonmodal inline error. Do not present an unapplied preference as active.
- **Notification authorization denied:** show status and Open Notification Settings.
- **Corrupt transfer history:** quarantine the file and recover with empty history.
- **Cache scan fails:** show usage as unavailable and log the error.
- **Cache deletion fails:** show the filesystem error and do not report success.
- **Rclone path changes:** mark restart required without interrupting active work.
- **Daemon restart fails:** preserve the chosen binary path and expose the daemon error with Retry.

## View Structure

SettingsView owns only tab selection and window-level sizing. Each destination is a separate view with narrow environment dependencies:

- GeneralSettingsView
- TransferSettingsView
- AdvancedSettingsView

Within a pane, substantial sections are separate View types rather than computed view properties. Shared preference rows continue to use the existing FormSection and FormRow primitives. Async state such as cache usage, notification authorization, and daemon status belongs to focused observable services or models rather than the root Settings view.

## Accessibility And Localization

- All controls use visible FormRow labels or explicit accessibility labels.
- Error text is associated with the affected control.
- Keyboard traversal follows visual order.
- Destructive actions identify their effect before confirmation.
- User-facing literals use SwiftUI-localizable strings; runtime paths and error messages render verbatim.
- Pane content remains usable at the largest supported accessibility text size via vertical scrolling rather than clipped fixed heights.

## Verification

### Automated

- AppSettings default values, persistence, and enum round-trips with isolated defaults.
- New mount creation consumes defaults; mount editing preserves existing values.
- Manually added and imported remotes honor the Finder default without changing existing domains.
- New copy requests inherit the conflict default; per-operation overrides win.
- Transfer history JSON round-trip and atomic persistence.
- Retention pruning for 7 days, 30 days, Forever, and Until Nimbus Quits.
- Active transfers are excluded from persisted history.
- Corrupt history is quarantined and replaced with empty state.
- Notification modes and denied authorization using an injected notification client.
- Rclone version, restart-required, restart success, and restart failure state transitions.
- Snapshot coverage for all three panes, error/validation states, long binary paths, and large text.

### Manual

- Render every pane in light and dark appearance.
- Run the real Settings window and compare against the approved three-pane mockup.
- Verify keyboard traversal and VoiceOver labels.
- Deny notification permission and verify the recovery path.
- Create and import remotes with Finder default on and off.
- Create a mount and verify defaults; edit an existing mount and verify no default overwrites it.
- Change the conflict preference and confirm new operations initialize correctly.
- Quit and relaunch to verify transfer-history retention.
- Confirm no existing remote domain or mount changes when a global default changes.

## Delivery Boundary

Implementation may land in small verified increments, but the feature is complete only when all three panes use the new information architecture and every visible preference is wired to its specified behavior. Controls without real application behavior must not ship.
