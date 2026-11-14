# Dock icon, idle disconnect, and downloaded-file storage

Date: 2026-11-14 · Status: implemented

Three small quality-of-life features requested together.

## 1. Show Nimbus in the Dock (toggle)

- `AppSettings.showsDockIcon`, default **on** (current behaviour).
- Off: the app runs as `.accessory` (menu bar only). The menu bar companion is
  always present, so the app stays reachable.
- One policy helper, `DockPolicy.apply(settings)`, replaces every hard-coded
  `setActivationPolicy(.regular)` (reopen, router `open`, notification click,
  background takeover). Login/background/Finder launches still start hidden as
  `.accessory`; showing a window restores `.regular` only when the setting is on.
- UI: General → Nimbus → "Show in Dock".

## 2. Disconnect when idle, reconnect from Finder

"Connection" = the `rclone rcd` daemon the app spawns. The NFS
`rclone serve nfs` children are separate processes and are not touched.

### Idle disconnect

- `AppSettings.idleDisconnect: IdleDisconnect` — `never` (default), 5, 15, 30, 60 min.
- `IdleDisconnectController` (app, `@MainActor @Observable`) ticks every 15 s.
  Activity that resets the clock:
  - a visible Nimbus window (main or Settings);
  - active transfers, or a backup running/queued;
  - a mounted network drive (keeps it simple: drives need the daemon's remotes);
  - a wake ping from the File Provider extension (Finder used a drive).
- When the clock passes the timeout, the daemon goes to sleep:
  `RcloneDaemon.sleep()` stops the process and sets `status = .asleep`
  (distinct from `.idle`/`.error`, so no error UI). Periodic cloud refresh and
  the remote-change ticker pause while asleep.
- Wake (`RcloneDaemon.wake`) restarts with the current settings; the existing
  `.task(id: daemon.status)` resync (shared state, domains, mounts) runs as on
  any reconnect. Wake triggers: a Nimbus window appears, the menu bar companion
  opens, a backup is enqueued, a Shortcut runs, or a Finder ping.

### Finder reconnect (auto connect)

- Shared `NimbusWake` (compiled into app + extension):
  - Darwin notification `53MUTM55LC.app.casavargas.nimbus.wake`.
  - `finder-wake.json` in the group container: `{ opensApp: Bool }`, written by
    the app (setting "Open Nimbus when a drive is used in Finder", default on).
  - `finder-launch-request` marker: timestamp written by the extension right
    before it launches the app.
- Extension: every `withRetry` posts the wake notification (throttled to once
  per 20 s) so Finder use keeps the daemon awake and wakes a sleeping one. When
  the first attempt fails and Nimbus isn't running and `opensApp` is on, it
  writes the marker and launches the containing app with `activates = false`.
  The retry ladder (1+2+3+4 s) then picks up the new port from shared state.
- The working-set change scanner does not ping (it would keep the daemon awake
  forever).
- App: a launch with a marker newer than 60 s behaves like a login launch —
  windows hidden, `.accessory`, daemon + drives started.

## 3. Downloaded files per drive

- New Settings section "Downloaded files" (General tab): one row per Finder
  drive (File Provider domain) with the bytes of downloaded files, plus a total.
- Size = sum of `documentSize` over the domain's materialized-items enumerator
  (no directory walk: walking a File Provider folder would make Finder list the
  whole cloud).
- "Remove Downloads" per drive and "Remove All Downloads": `evictItem` for every
  materialized non-folder item that isn't pinned (Keep Downloaded) — files stay
  in the cloud and in Finder as placeholders. Items the system refuses to evict
  (open, unsynced edits) are skipped and counted; the row says how many.
- Confirmation dialog before removing.

## Tests

- `AppSettings` round-trips the new prefs.
- `IdleDisconnectPolicy` (pure): sleeps only past timeout with no activity;
  never with `.never`.
- `NimbusWake` launch-marker freshness.
- `DownloadedStorage` summing/eviction planning over fake items (pinned skipped).
