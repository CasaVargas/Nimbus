# Settings Polish (Phase 4) — Design

**Date:** 2026-11-08
**Status:** Approved direction ("write spec and build", 2026-11-08)
**Builds on:** `2026-08-24-settings-redesign-design.md` (the three panes, and the rule that
every preference has to change real behavior) and `2026-11-08-home-and-companion-design.md`
(the plain-language vocabulary)

## Why

Home, the menu bar companion and Add Cloud now speak plainly. Settings still uses rclone's
vocabulary ("Add New Remotes to Finder", "Mount New Volumes at Login", "Daemon", "Port",
"Binary Path"), asks for rclone's number syntax ("k, M, G, or T suffix"), and labels a
troubleshooting reset ("Clear Sync Data") as if it were storage. The layout is already native.
The work is mostly words, simpler controls, and putting each setting where someone would look
for it.

## Goals

1. Every label is a plain sentence fragment a non-technical person can act on.
2. No control needs rclone syntax. A speed limit is a menu, with Custom as the escape hatch.
3. Advanced reads like the rest of the app: one status line for the connection engine, then
   the rclone details for people who want them.
4. Settings groups look like Home's: sentence-case headings, hairline borders, a divider
   between rows.
5. Settings snapshot tests render identically on every machine.

## Non-goals

- New preferences that don't change real behavior.
- Per-cloud settings. Those live on each cloud's page in the main window.
- A sidebar-style Settings window. Toolbar tabs remain correct for three panes on macOS.
- Changing what any existing preference does, or its `UserDefaults` key.

## Shared: `FormSection`

- The title becomes `Typography.headline`, sentence case, primary color. It replaces the
  uppercase secondary caption. This affects every form in the app (Add Cloud pages, Edit Cloud,
  Add Network Drive), which is intended for cohesion.
- The group gets a hairline `separator` border, and adjacent rows are separated by a `Divider`
  (built with `Group(subviews:)`), matching `HomeGroup`.
- The footer stays a caption, in secondary color.

## General

| Section | Row | Control | Backing |
|---|---|---|---|
| Nimbus | Open at Login | switch | `LaunchAtLoginService` (same words as the companion's gear menu) |
| | Appearance | System / Light / Dark | `AppSettings.appearance` |
| New clouds | Show new clouds in Finder | switch | `AppSettings.addNewRemotesToFinder` |
| | footer | "Clouds you already have keep their own setting. Change one from its page in Nimbus." | |
| About | icon, "Nimbus", "Version x (build)", "© 2026 CasaVargas LLC" | | |
| | links | Website · Source Code · License · Built on rclone | casavargas.app, the GitHub repo, its LICENSE, rclone.org |

The network-drive defaults and the sync-data reset move to Advanced.

## Transfers

| Section | Row | Control |
|---|---|---|
| Speed | Copies at once | stepper 1–32. Help: "More is faster on a fast connection; fewer is gentler on your Mac and network." |
| | Speed limit | menu: No limit, 1 MB/s, 5 MB/s, 10 MB/s, 25 MB/s, 50 MB/s, Custom… |
| Copying | If a file already exists | Keep Both / Skip / Replace (Finder's words for rename / skip / overwrite). Help: "You can still choose differently for each copy." |
| Notifications and activity | Notify me | When something fails / After every copy / Never, plus the existing permission row |
| | Keep activity for | 7 days / 30 days / Until Nimbus quits / Forever |

**Speed limit mapping** (`SpeedLimitChoice`, pure and unit-tested). rclone `--bwlimit` values
are bytes per second with binary suffixes, so `"5M"` means 5 MiB/s. The menu says "MB/s" because
that's how people read speeds, and the difference doesn't matter for a limit.

- `""` ↔ No limit. `"1M"`, `"5M"`, `"10M"`, `"25M"`, `"50M"` ↔ their presets.
- Anything else non-empty ↔ Custom, with a text field showing the stored value.
- Custom keeps today's validator and runtime apply path (`TransferRuntimeSettings`). The
  error reads "Enter a speed like 500k, 2M or 1.5G (bytes per second)."
- Picking a preset applies immediately through the same path. Errors show inline, as today.

## Advanced

| Section | Rows |
|---|---|
| Connection engine | One status row: a dot and "Running", "Starting…", "Stopped", or the error text, with "rclone 1.76 on port 5572" under it, and the action button (Start / Restart / Retry / Restart Now) trailing. When a restart is needed: "Restart to use the rclone you chose." |
| rclone | Location (path, Choose…, Reveal) · Version |
| Network drives | Access for new network drives (Read & write / Read only) · Connect new network drives at login. Footer: "Applies to network drives you add later. Most people use Show in Finder instead." |
| Troubleshooting | Finder change records (size) with **Reset…** · Logs (**Open in Console**) · **Copy System Information**. Footer: "System information leaves out cloud names, passwords, and file paths." |

**Reset wording.** The help text reads "Nimbus remembers what Finder has already seen so it
only shows changes. Resetting makes Finder check every folder again. Your files aren't touched."
The confirmation is titled "Reset Finder change records?" and its button is **Reset**. The
behavior is exactly today's `FileProviderSyncCacheStore.clearCache()`.

## Snapshot determinism

The Settings snapshots flaked for two reasons. Both are now fixed in `SnapshotHelpers`:

1. **Display scale.** `bitmapImageRepForCachingDisplay` follows the screen's backing scale, so
   the same test made 1x images on a non-Retina display or CI's virtual display and 2x on a
   Retina Mac. Captures now go into an explicit 2x `NSBitmapImageRep`.
2. **A shared window across concurrent suites.** Swift Testing runs suites concurrently on the
   main actor. While one hosted render spun the run loop, another test swapped its own view
   into the shared window, and the first captured a detached view that fell back to the light
   default appearance. This was the "depends on test ordering" flake. Every render now gets
   its own window.

A mismatch also writes the losing render to `$TMPDIR/nimbus-snapshot-failures/<name>.png`
and prints the path. All Settings fixtures were re-recorded, the full suite passed 4 runs in
a row locally, and the 6 Settings `-skip-testing` entries are removed from `ci.yml`.

## Exit gates

- `SpeedLimitChoice` tests: presets round-trip, unknown values map to Custom, empty maps to
  No limit, and preset values pass `BandwidthLimitValidator`.
- Settings snapshot fixtures re-recorded, and the full suite green apart from the documented
  `EmptyState` failure.
- RenderPreview of all three panes, light and dark.
- A grep finds no "remote", "mount", "volume", "daemon", or "binary" in General's or Transfers'
  user-facing strings.
